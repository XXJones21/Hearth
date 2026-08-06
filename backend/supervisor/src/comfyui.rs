use std::fs::{self, File};
use std::net::{SocketAddr, TcpStream};
use std::path::PathBuf;
use std::process::Stdio;
use std::time::{Duration, Instant};

use anyhow::{anyhow, Context, Result};
use serde_json::{json, Value};
use thiserror::Error;
use tokio::process::{Child, Command};
use tokio::time::{sleep, timeout};
use tracing::{info, warn};

use crate::config::ServerConfig;

/// Supervises a ComfyUI server process for the Engram harness.
///
/// Mirrors the conventions of `LlamaSupervisor` in `llama.rs`:
/// - env-driven config, no TOML
/// - multi-tiered health gates (TCP -> /system_stats)
/// - external-listener adoption when the port is already busy
/// - graceful kill on shutdown / persona-style swap
/// - a `job_started_at` field so `main.rs`'s stuck-slot watchdog can
///   force-restart wedged jobs (long-running video gen is the common case)
pub struct ComfyUISupervisor {
    config: ServerConfig,
    child: Option<Child>,
    external_ready: bool,
    job_started_at: Option<Instant>,
    last_completion_at: Option<Instant>,
}

#[derive(Debug, Error)]
pub enum ComfyError {
    #[error("ComfyUI request timed out after {timeout_s}s")]
    Timeout { timeout_s: u64 },
    #[error("ComfyUI request failed: {0}")]
    Request(String),
    #[error("ComfyUI returned {status}: {body}")]
    Http { status: u16, body: String },
    #[error("ComfyUI response was invalid: {0}")]
    InvalidResponse(String),
    #[error("ComfyUI workflow rejected: {0}")]
    InvalidWorkflow(String),
    #[error("ComfyUI out of memory: {0}")]
    OutOfMemory(String),
    #[error("ComfyUI restart failed after error: {original}; restart error: {restart}")]
    RestartFailed { original: String, restart: String },
}

impl ComfyError {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::Timeout { .. } => "timeout",
            Self::Request(_) => "request",
            Self::Http { .. } => "http",
            Self::InvalidResponse(_) => "invalid_response",
            Self::InvalidWorkflow(_) => "invalid_workflow",
            Self::OutOfMemory(_) => "out_of_memory",
            Self::RestartFailed { .. } => "restart_failed",
        }
    }

    pub fn is_recoverable(&self) -> bool {
        match self {
            Self::Timeout { .. } | Self::Request(_) | Self::OutOfMemory(_) => true,
            Self::Http { status, .. } => *status >= 500 || *status == 408 || *status == 429,
            Self::InvalidResponse(_) | Self::InvalidWorkflow(_) | Self::RestartFailed { .. } => {
                false
            }
        }
    }
}

#[derive(Debug)]
pub struct SubmitResult {
    pub prompt_id: String,
    pub number: Option<u64>,
}

impl ComfyUISupervisor {
    pub fn new(config: ServerConfig) -> Self {
        Self {
            config,
            child: None,
            external_ready: false,
            job_started_at: None,
            last_completion_at: None,
        }
    }

    /// Set whenever a /comfy/submit is in flight; cleared on success or error.
    /// Used by the stuck-slot watchdog (see `main.rs`).
    pub fn job_in_flight_since(&self) -> Option<Duration> {
        self.job_started_at.map(|t| t.elapsed())
    }

    pub async fn force_restart(&mut self) -> bool {
        if self.child.is_some() {
            warn!("stuck-slot watchdog: force-killing supervised ComfyUI");
            self.stop().await;
            true
        } else {
            false
        }
    }

    pub async fn is_ready(&mut self) -> bool {
        if let Some(child) = &mut self.child {
            match child.try_wait() {
                Ok(Some(_)) => {
                    self.child = None;
                    self.external_ready = false;
                    false
                }
                Ok(None) => true,
                Err(_) => false,
            }
        } else if self.external_ready {
            if self.existing_listener_ready().await {
                true
            } else {
                self.external_ready = false;
                false
            }
        } else {
            false
        }
    }

    pub async fn ensure_started(&mut self) -> Result<()> {
        if self.is_ready().await {
            return Ok(());
        }
        if self.config.comfy_external {
            if self.wait_existing_listener_ready().await {
                info!(
                    "using externally managed ComfyUI on {}:{} (COMFYUI_EXTERNAL=1)",
                    self.config.comfy_host, self.config.comfy_port
                );
                self.external_ready = true;
                return Ok(());
            }
            return Err(anyhow!(
                "COMFYUI_EXTERNAL=1 but no listener answered probes at {}:{} within {}s",
                self.config.comfy_host,
                self.config.comfy_port,
                self.config.comfy_health_timeout_s
            ));
        }
        if self.port_is_busy() {
            if self.wait_existing_listener_ready().await {
                info!(
                    "adopted externally launched ComfyUI on {}:{}",
                    self.config.comfy_host, self.config.comfy_port
                );
                self.external_ready = true;
                return Ok(());
            }
            return Err(anyhow!(
                "ComfyUI port {}:{} is already accepting connections but did not answer /system_stats. Stop the stale process or set COMFYUI_EXTERNAL=1.",
                self.config.comfy_host, self.config.comfy_port
            ));
        }
        let path = self
            .config
            .comfy_path
            .as_ref()
            .ok_or_else(|| anyhow!("COMFYUI_PATH not set; cannot spawn ComfyUI"))?;
        if !path.exists() {
            return Err(anyhow!(
                "COMFYUI_PATH does not exist: {}",
                path.display()
            ));
        }
        self.spawn_comfy(path.clone()).await?;
        self.wait_ready().await
    }

    pub async fn stop(&mut self) {
        if let Some(mut child) = self.child.take() {
            if child.start_kill().is_ok() {
                let _ = child.wait().await;
            }
        }
        self.external_ready = false;
    }

    /// Submit a workflow graph to ComfyUI's /prompt endpoint.
    pub async fn submit(
        &mut self,
        graph: Value,
        client_id: &str,
    ) -> std::result::Result<SubmitResult, ComfyError> {
        let client = reqwest::Client::new();
        let url = format!("{}/prompt", self.config.comfy_base_url());
        let payload = json!({ "prompt": graph, "client_id": client_id });
        let started = Instant::now();
        self.job_started_at = Some(started);
        let result = timeout(self.config.comfy_submit_timeout(), async {
            let response = client
                .post(&url)
                .json(&payload)
                .send()
                .await
                .map_err(|err| ComfyError::Request(err.to_string()))?;
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            if !status.is_success() {
                let lower = body.to_ascii_lowercase();
                if status.as_u16() == 400 && lower.contains("node") {
                    return Err(ComfyError::InvalidWorkflow(body));
                }
                if lower.contains("cuda out of memory") || lower.contains("oom") {
                    return Err(ComfyError::OutOfMemory(body));
                }
                return Err(ComfyError::Http {
                    status: status.as_u16(),
                    body,
                });
            }
            serde_json::from_str::<Value>(&body)
                .map_err(|err| ComfyError::InvalidResponse(err.to_string()))
        })
        .await;
        self.job_started_at = None;
        self.last_completion_at = Some(Instant::now());

        let body = match result {
            Ok(inner) => inner?,
            Err(_) => {
                return Err(ComfyError::Timeout {
                    timeout_s: self.config.comfy_submit_timeout().as_secs(),
                })
            }
        };
        let prompt_id = body
            .get("prompt_id")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                ComfyError::InvalidResponse(format!("submit returned no prompt_id: {}", body))
            })?
            .to_string();
        let number = body.get("number").and_then(Value::as_u64);
        Ok(SubmitResult { prompt_id, number })
    }

    pub async fn fetch_history(&self, prompt_id: &str) -> std::result::Result<Value, ComfyError> {
        let client = reqwest::Client::new();
        let url = format!("{}/history/{}", self.config.comfy_base_url(), prompt_id);
        let response = client
            .get(&url)
            .timeout(Duration::from_secs(15))
            .send()
            .await
            .map_err(|err| ComfyError::Request(err.to_string()))?;
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        if !status.is_success() {
            return Err(ComfyError::Http {
                status: status.as_u16(),
                body,
            });
        }
        serde_json::from_str::<Value>(&body)
            .map_err(|err| ComfyError::InvalidResponse(err.to_string()))
    }

    pub fn comfy_base_url(&self) -> String {
        self.config.comfy_base_url()
    }

    // --- internals ------------------------------------------------------

    async fn spawn_comfy(&mut self, comfy_path: PathBuf) -> Result<()> {
        fs::create_dir_all(self.config.log_dir())?;
        let stdout = File::create(self.config.log_dir().join("comfyui.out.log"))?;
        let stderr = File::create(self.config.log_dir().join("comfyui.err.log"))?;

        let python = &self.config.comfy_python;
        let mut cmd = Command::new(python);
        cmd.arg(comfy_path.join("main.py"))
            .arg("--listen")
            .arg(&self.config.comfy_host)
            .arg("--port")
            .arg(self.config.comfy_port.to_string());
        if let Some(extra) = &self.config.comfy_extra_args {
            for arg in extra.split_whitespace() {
                cmd.arg(arg);
            }
        }
        info!(
            "starting ComfyUI: {} {} --listen {} --port {}",
            python.display(),
            comfy_path.join("main.py").display(),
            self.config.comfy_host,
            self.config.comfy_port
        );
        let child = cmd
            .current_dir(&comfy_path)
            .stdout(Stdio::from(stdout))
            .stderr(Stdio::from(stderr))
            .spawn()
            .context("spawn ComfyUI")?;
        self.child = Some(child);
        Ok(())
    }

    async fn wait_ready(&mut self) -> Result<()> {
        let client = reqwest::Client::new();
        let deadline = Instant::now() + self.config.comfy_health_timeout();
        while Instant::now() < deadline {
            if let Some(child) = &mut self.child {
                if let Some(status) = child.try_wait().context("poll ComfyUI child")? {
                    self.child = None;
                    return Err(anyhow!("ComfyUI exited before ready: {}", status));
                }
            }
            if self.system_stats_ready(&client).await {
                info!("ComfyUI /system_stats healthy");
                return Ok(());
            }
            sleep(Duration::from_secs(1)).await;
        }
        Err(anyhow!(
            "ComfyUI did not become ready within {}s",
            self.config.comfy_health_timeout_s
        ))
    }

    async fn system_stats_ready(&self, client: &reqwest::Client) -> bool {
        match client
            .get(self.config.comfy_system_stats_url())
            .timeout(Duration::from_secs(3))
            .send()
            .await
        {
            Ok(resp) if resp.status().is_success() => true,
            Ok(resp) => {
                warn!("ComfyUI /system_stats returned {}", resp.status());
                false
            }
            Err(err) => {
                warn!("ComfyUI /system_stats pending: {}", err);
                false
            }
        }
    }

    fn port_is_busy(&self) -> bool {
        let addr = format!("{}:{}", self.config.comfy_host, self.config.comfy_port);
        match addr.parse::<SocketAddr>() {
            Ok(socket) => TcpStream::connect_timeout(&socket, Duration::from_millis(200)).is_ok(),
            Err(_) => false,
        }
    }

    async fn existing_listener_ready(&self) -> bool {
        let client = reqwest::Client::new();
        self.system_stats_ready(&client).await
    }

    async fn wait_existing_listener_ready(&self) -> bool {
        let deadline = Instant::now() + self.config.comfy_health_timeout();
        while Instant::now() < deadline {
            if self.existing_listener_ready().await {
                return true;
            }
            sleep(Duration::from_secs(1)).await;
        }
        false
    }
}

/// One-shot diagnostic dump for `--probe-runtime` / `--print-config`.
#[allow(dead_code)]
pub async fn probe_comfy(config: &ServerConfig) -> Value {
    let client = reqwest::Client::new();
    let url = config.comfy_system_stats_url();
    let probe = match client
        .get(&url)
        .timeout(Duration::from_secs(5))
        .send()
        .await
    {
        Ok(resp) => json!({
            "ok": resp.status().is_success(),
            "status": resp.status().as_u16(),
            "url": url,
        }),
        Err(err) => json!({
            "ok": false,
            "url": url,
            "error": err.to_string(),
        }),
    };
    json!({
        "system_stats": probe,
        "host": config.comfy_host,
        "port": config.comfy_port,
        "path": config.comfy_path.as_ref().map(|p| p.display().to_string()),
        "external": config.comfy_external,
    })
}
