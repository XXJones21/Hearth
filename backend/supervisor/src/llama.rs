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

use crate::config::{resolve_repo_path, ServerConfig};

pub struct LlamaSupervisor {
    config: ServerConfig,
    child: Option<Child>,
    active_model: Option<ModelSpec>,
    external_ready: bool,
    /// Set when a chat completion is in flight; cleared on success or error.
    /// Used by the stuck-slot watchdog (see `main.rs`) to surface chats that
    /// outlive 2x `direct_chat_timeout`, which indicates a wedged llama slot
    /// that the per-call timeout did not break cleanly.
    chat_started_at: Option<Instant>,
    last_completion_at: Option<Instant>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ModelSpec {
    path: PathBuf,
    mmproj_path: Option<PathBuf>,
    n_gpu_layers: i64,
    n_ctx: u64,
    n_cpu_moe: Option<u64>,
    kv_cache_type: Option<String>,
    override_tensor: Option<String>,
}

#[derive(Debug)]
pub struct ChatCompletion {
    pub body: Value,
    pub elapsed: Duration,
}

#[derive(Debug, Error)]
pub enum LlamaChatError {
    #[error("llama-server chat timed out after {timeout_s}s")]
    Timeout { timeout_s: u64 },
    #[error("llama-server chat request failed: {0}")]
    Request(String),
    #[error("llama-server chat failed with {status}: {body}")]
    Http { status: u16, body: String },
    #[error("llama-server chat response was invalid: {0}")]
    InvalidResponse(String),
    #[error("adopted llama-server listener is dirty after failed chat: {original}")]
    ExternalDirty { original: String },
    #[error("llama-server restart failed after chat error: {original}; restart error: {restart}")]
    RestartFailed { original: String, restart: String },
}

impl LlamaChatError {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::Timeout { .. } => "timeout",
            Self::Request(_) => "request",
            Self::Http { .. } => "http",
            Self::InvalidResponse(_) => "invalid_response",
            Self::ExternalDirty { .. } => "external_dirty",
            Self::RestartFailed { .. } => "restart_failed",
        }
    }

    fn is_recoverable(&self) -> bool {
        match self {
            Self::Timeout { .. } | Self::Request(_) => true,
            Self::Http { status, .. } => *status >= 500 || *status == 408 || *status == 429,
            Self::InvalidResponse(_) | Self::ExternalDirty { .. } | Self::RestartFailed { .. } => {
                false
            }
        }
    }
}

impl LlamaSupervisor {
    pub fn new(config: ServerConfig) -> Self {
        Self {
            config,
            child: None,
            active_model: None,
            external_ready: false,
            chat_started_at: None,
            last_completion_at: None,
        }
    }

    /// When a chat is currently in flight, returns how long it has been
    /// running. None when idle. Used by the stuck-slot watchdog.
    pub fn chat_in_flight_since(&self) -> Option<Duration> {
        self.chat_started_at.map(|t| t.elapsed())
    }

    /// Force-stops the supervised llama-server child if one is running,
    /// returning whether anything was killed. Intended for the watchdog
    /// to break a wedged slot. The next chat call will trigger a
    /// recoverable-error restart through `ensure_started_for`.
    pub async fn force_restart(&mut self) -> bool {
        if self.child.is_some() {
            warn!("stuck-slot watchdog: force-killing supervised llama-server");
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

    pub fn active_model_label(&self) -> Option<String> {
        self.active_model
            .as_ref()
            .map(|model| model.path.display().to_string())
    }

    pub async fn ensure_started_for(&mut self, persona_config: &Value) -> Result<()> {
        let candidates = self.model_candidates(persona_config)?;
        if self.is_ready().await
            && self
                .active_model
                .as_ref()
                .is_some_and(|active| candidates.iter().any(|candidate| candidate == active))
        {
            return Ok(());
        }
        if self.child.is_some() {
            info!("persona model changed; restarting llama-server");
            self.stop().await;
        }
        if self.port_is_busy() {
            if self.wait_existing_listener_ready().await {
                info!(
                    "using externally managed llama-server on {}:{}",
                    self.config.llama_host, self.config.llama_port
                );
                self.external_ready = true;
                self.active_model = candidates.first().cloned();
                return Ok(());
            }
            return Err(self.existing_listener_error().await);
        }
        if !self.config.llama_server_bin.exists() {
            return Err(anyhow!(
                "WSL-native llama-server not found at {}",
                self.config.llama_server_bin.display()
            ));
        }

        let mut errors = Vec::new();
        for candidate in candidates {
            if !candidate.path.exists() {
                errors.push(format!(
                    "model file not found: {}",
                    candidate.path.display()
                ));
                continue;
            }
            match self.start_model(candidate.clone()).await {
                Ok(()) => {
                    self.active_model = Some(candidate);
                    return Ok(());
                }
                Err(err) => {
                    warn!("llama-server start failed: {}", err);
                    errors.push(err.to_string());
                    self.stop().await;
                }
            }
        }

        Err(anyhow!(
            "no configured llama model became ready: {}",
            errors.join("; ")
        ))
    }

    pub async fn chat_completion(
        &mut self,
        persona_config: &Value,
        payload: Value,
    ) -> std::result::Result<ChatCompletion, LlamaChatError> {
        self.post_chat_completion(payload, Some(persona_config))
            .await
    }

    pub async fn chat_completion_raw(
        &mut self,
        payload: Value,
    ) -> std::result::Result<ChatCompletion, LlamaChatError> {
        self.post_chat_completion(payload, None).await
    }

    async fn post_chat_completion(
        &mut self,
        payload: Value,
        persona_config: Option<&Value>,
    ) -> std::result::Result<ChatCompletion, LlamaChatError> {
        let client = reqwest::Client::new();
        let url = format!(
            "{}/chat/completions",
            self.config.llama_base_url.trim_end_matches('/')
        );
        let started = Instant::now();
        self.chat_started_at = Some(started);
        let result =
            post_chat_payload(&client, &url, payload, self.config.direct_chat_timeout()).await;
        self.chat_started_at = None;
        self.last_completion_at = Some(Instant::now());
        match result {
            Ok(body) => Ok(ChatCompletion {
                body,
                elapsed: started.elapsed(),
            }),
            Err(err) => {
                if err.is_recoverable() {
                    let original = err.to_string();
                    if self.child.is_some() {
                        warn!(
                            "direct llama chat failed; restarting supervised llama-server: {}",
                            original
                        );
                        let active_model = self.active_model.clone();
                        self.stop().await;
                        let restart_result = if let Some(persona_config) = persona_config {
                            self.ensure_started_for(persona_config).await
                        } else if let Some(model) = active_model {
                            let result = self.start_model(model.clone()).await;
                            if result.is_ok() {
                                self.active_model = Some(model);
                            }
                            result
                        } else {
                            Err(anyhow!("no active llama model available for restart"))
                        };
                        if let Err(restart_err) = restart_result {
                            return Err(LlamaChatError::RestartFailed {
                                original,
                                restart: restart_err.to_string(),
                            });
                        }
                    } else if self.external_ready {
                        self.external_ready = false;
                        self.active_model = None;
                        return Err(LlamaChatError::ExternalDirty { original });
                    }
                }
                Err(err)
            }
        }
    }

    async fn start_model(&mut self, model: ModelSpec) -> Result<()> {
        fs::create_dir_all(self.config.log_dir())?;
        let stdout = File::create(self.config.log_dir().join("llama-server.out.log"))?;
        let stderr = File::create(self.config.log_dir().join("llama-server.err.log"))?;

        let mut cmd = Command::new(&self.config.llama_server_bin);
        cmd.arg("--model")
            .arg(&model.path)
            .arg("--n-gpu-layers")
            .arg(model.n_gpu_layers.to_string())
            .arg("--ctx-size")
            .arg(model.n_ctx.to_string())
            .arg("--host")
            .arg(&self.config.llama_host)
            .arg("--port")
            .arg(self.config.llama_port.to_string())
            .arg("--parallel")
            .arg(self.config.llama_parallel.to_string());

        if let Some(n) = model.n_cpu_moe {
            cmd.arg("--n-cpu-moe").arg(n.to_string());
        }
        if let Some(pattern) = &model.override_tensor {
            cmd.arg("-ot").arg(pattern);
        }

        let kv = model
            .kv_cache_type
            .as_deref()
            .unwrap_or(self.config.kv_cache_type.as_str());
        if kv != "f16" {
            cmd.arg("--cache-type-k")
                .arg(kv)
                .arg("--cache-type-v")
                .arg(kv);
            cmd.arg("-fa").arg("on");
        }
        if self.config.llama_no_warmup {
            cmd.arg("--no-warmup");
        }
        cmd.arg("--reasoning").arg(&self.config.llama_reasoning);
        if self.config.llama_reasoning == "off" {
            cmd.arg("--reasoning-budget").arg("0");
        }
        // Disable the server-side prompt cache. It accumulates large recurrent-state (RS)
        // checkpoints (~150 MiB each) from completed sessions and never evicts them between
        // restarts, causing 1-2 second eviction stalls and fragmented VRAM on new sessions.
        // Intra-session KV reuse still works through the single parallel slot.
        cmd.arg("--cache-ram").arg("0");
        if let Some(draft_path) = &self.config.spec_draft_model {
            cmd.arg("-md")
                .arg(draft_path)
                .arg("-ngld")
                .arg("99")
                .arg("-cd")
                .arg("4096")
                .arg("--draft-max")
                .arg("12")
                .arg("--draft-min")
                .arg("3")
                .arg("--draft-p-min")
                .arg("0.6");
        }
        if let Some(mmproj_path) = &model.mmproj_path {
            cmd.arg("--mmproj").arg(mmproj_path);
        }
        if self.config.llama_cuda_unified_memory {
            cmd.env("GGML_CUDA_ENABLE_UNIFIED_MEMORY", "1");
        }

        info!(
            "starting llama-server with model {}: {:?}",
            model.path.display(),
            cmd.as_std()
        );
        let child = cmd
            .current_dir(&self.config.repo_root)
            .stdout(Stdio::from(stdout))
            .stderr(Stdio::from(stderr))
            .spawn()
            .context("spawn llama-server")?;
        self.child = Some(child);
        self.wait_ready().await
    }

    pub async fn stop(&mut self) {
        if let Some(mut child) = self.child.take() {
            if child.start_kill().is_ok() {
                let _ = child.wait().await;
            }
        }
        self.external_ready = false;
        self.active_model = None;
    }

    async fn wait_ready(&mut self) -> Result<()> {
        let client = reqwest::Client::new();
        let deadline = Instant::now() + self.config.health_timeout();
        while Instant::now() < deadline {
            if let Some(child) = &mut self.child {
                if let Some(status) = child.try_wait().context("poll llama-server child")? {
                    self.child = None;
                    return Err(anyhow!(
                        "llama-server exited before becoming ready: {}",
                        status
                    ));
                }
            }
            let health_ok = match client
                .get(self.config.llama_health_url())
                .timeout(Duration::from_secs(2))
                .send()
                .await
            {
                Ok(resp) if resp.status().is_success() => true,
                Ok(resp) => {
                    warn!("llama health returned {}", resp.status());
                    false
                }
                Err(err) => {
                    warn!("llama health pending: {}", err);
                    false
                }
            };
            if health_ok && self.models_ready(&client).await && self.chat_smoke_ready(&client).await
            {
                info!("llama-server health, /v1/models, and chat smoke checks passed");
                return Ok(());
            }
            sleep(Duration::from_secs(1)).await;
        }
        Err(anyhow!(
            "llama-server did not become ready within {}s",
            self.config.llama_health_timeout_s
        ))
    }

    async fn models_ready(&self, client: &reqwest::Client) -> bool {
        match client
            .get(self.config.llama_models_url())
            .timeout(Duration::from_secs(2))
            .send()
            .await
        {
            Ok(resp) if resp.status().is_success() => match resp.json::<Value>().await {
                Ok(body) => body
                    .get("data")
                    .and_then(Value::as_array)
                    .is_some_and(|models| !models.is_empty()),
                Err(err) => {
                    warn!("llama /v1/models JSON pending: {}", err);
                    false
                }
            },
            Ok(resp) => {
                warn!("llama /v1/models returned {}", resp.status());
                false
            }
            Err(err) => {
                warn!("llama /v1/models pending: {}", err);
                false
            }
        }
    }

    async fn chat_smoke_ready(&self, client: &reqwest::Client) -> bool {
        let url = format!(
            "{}/chat/completions",
            self.config.llama_base_url.trim_end_matches('/')
        );
        let payload = json!({
            "messages": [{"role": "user", "content": "Reply with exactly: OK"}],
            "temperature": 0.0,
            "max_tokens": 2,
            "chat_template_kwargs": {
                "enable_thinking": false,
            },
        });
        match post_chat_payload(client, &url, payload, self.config.direct_smoke_timeout()).await {
            Ok(body) => {
                let valid_completion = body
                    .get("choices")
                    .and_then(Value::as_array)
                    .is_some_and(|choices| !choices.is_empty());
                if !valid_completion {
                    warn!("llama chat smoke response missing choices");
                }
                valid_completion
            }
            Err(err) => {
                warn!("llama chat smoke pending: {}", err);
                false
            }
        }
    }

    fn model_candidates(&self, persona_config: &Value) -> Result<Vec<ModelSpec>> {
        let deep = persona_config
            .get("deep_model")
            .and_then(Value::as_object)
            .context("persona missing deep_model")?;
        // The persona owns offload depth; -1 (all layers) is the default every
        // current persona declares. Until 2026-08-04 this was hard-forced to -1
        // whenever the OpenCode harness flag was set, which was always, so the
        // persona value was never read. Honouring it is behaviour-identical
        // today and is what lets a smaller card get a partial offload.
        let n_gpu_layers = deep
            .get("n_gpu_layers")
            .and_then(Value::as_i64)
            .unwrap_or(-1);
        let persona_n_ctx = deep.get("n_ctx").and_then(Value::as_u64);
        let n_ctx = match (self.config.llama_ctx_override, persona_n_ctx) {
            (Some(override_ctx), Some(persona_ctx)) if override_ctx < persona_ctx => {
                warn!(
                    "HEARTH_LLAMA_CTX={} is below persona deep_model.n_ctx={}; \
                     using override but truncating context capacity",
                    override_ctx, persona_ctx
                );
                override_ctx
            }
            (Some(override_ctx), _) => override_ctx,
            (None, Some(persona_ctx)) => persona_ctx,
            (None, None) => 16384,
        };

        let env_cpu_moe = std::env::var("HEARTH_LLAMA_CPU_MOE")
            .ok()
            .and_then(|v| v.trim().parse::<u64>().ok())
            .filter(|n| *n > 0);
        let n_cpu_moe = env_cpu_moe.or_else(|| deep.get("n_cpu_moe").and_then(Value::as_u64));
        let kv_cache_type = deep
            .get("kv_cache_type")
            .and_then(Value::as_str)
            .map(|s| s.to_string());
        let env_override_tensor = std::env::var("HEARTH_LLAMA_OVERRIDE_TENSOR")
            .ok()
            .filter(|v| !v.trim().is_empty());
        let override_tensor = env_override_tensor.or_else(|| {
            deep.get("override_tensor")
                .and_then(Value::as_str)
                .map(|s| s.to_string())
        });

        if let Some(override_path) = std::env::var("HEARTH_DEEP_MODEL_OVERRIDE")
            .ok()
            .filter(|v| !v.trim().is_empty())
        {
            let path = resolve_repo_path(&self.config.repo_root, &override_path);
            if path.exists() {
                return Ok(vec![ModelSpec {
                    path,
                    mmproj_path: None,
                    n_gpu_layers,
                    n_ctx,
                    n_cpu_moe,
                    kv_cache_type: kv_cache_type.clone(),
                    override_tensor: override_tensor.clone(),
                }]);
            }
            // Fail loudly rather than fall back. A silently ignored override
            // means you believe you are running model X while the resident
            // model is Y, which has cost this project a bench before.
            anyhow::bail!(
                "HEARTH_DEEP_MODEL_OVERRIDE points to missing file {}",
                path.display()
            );
        }

        let mut candidates = Vec::new();
        let mmproj_path = deep
            .get("mmproj_path")
            .and_then(Value::as_str)
            .map(|path| resolve_repo_path(&self.config.repo_root, path))
            .filter(|path| path.exists());
        // A persona names a model id; the dictionary says which file that is
        // and HEARTH_MODELS says where files live. "path" is still honoured so
        // a developer can point a persona at a file by hand, but nothing
        // shipped carries one, because an absolute path in a manifest is an
        // absolute path on exactly one machine.
        let mut raw_paths: Vec<String> = Vec::new();
        if let Some(model_id) = deep.get("id").and_then(Value::as_str) {
            match crate::models::resolve(&self.config.repo_root, model_id) {
                Some(path) => raw_paths.push(path.display().to_string()),
                None => anyhow::bail!(
                    "persona names model id {} but no dictionary entry describes it",
                    model_id
                ),
            }
        }
        for key in ["path", "fallback_path"] {
            if let Some(value) = deep.get(key).and_then(Value::as_str) {
                raw_paths.push(value.to_string());
            }
        }
        // The first candidate is the persona's own model and carries the
        // projector; anything after it is a fallback and does not.
        for (index, raw_path) in raw_paths.iter().enumerate() {
            let spec = ModelSpec {
                path: resolve_repo_path(&self.config.repo_root, raw_path),
                mmproj_path: if index == 0 { mmproj_path.clone() } else { None },
                n_gpu_layers,
                n_ctx,
                n_cpu_moe,
                kv_cache_type: kv_cache_type.clone(),
                override_tensor: override_tensor.clone(),
            };
            if !candidates.iter().any(|existing| existing == &spec) {
                candidates.push(spec);
            }
        }
        if candidates.is_empty() {
            anyhow::bail!("deep_model names neither an id nor a path");
        }
        Ok(candidates)
    }

    fn port_is_busy(&self) -> bool {
        let addr = format!("{}:{}", self.config.llama_host, self.config.llama_port);
        match addr.parse::<SocketAddr>() {
            Ok(socket) => TcpStream::connect_timeout(&socket, Duration::from_millis(200)).is_ok(),
            Err(_) => false,
        }
    }

    async fn existing_listener_error(&self) -> anyhow::Error {
        let client = reqwest::Client::new();
        let health = probe_get(&client, &self.config.llama_health_url()).await;
        let models = probe_get(&client, &self.config.llama_models_url()).await;
        let health_ok = health.get("ok").and_then(Value::as_bool).unwrap_or(false);
        let models_ok = models.get("ok").and_then(Value::as_bool).unwrap_or(false);
        let detail = if health_ok && models_ok {
            "the listener responds like llama-server, but Rust did not start it"
        } else if health_ok {
            "the listener answers /health but not /v1/models"
        } else {
            "the listener does not answer the expected llama-server probes"
        };
        anyhow!(
            "llama port {}:{} is already accepting connections; {}. Stop the stale process or choose another HEARTH_LLAMA_PORT before starting Rust supervision.",
            self.config.llama_host,
            self.config.llama_port,
            detail
        )
    }

    async fn existing_listener_ready(&self) -> bool {
        let client = reqwest::Client::new();
        let health = probe_get(&client, &self.config.llama_health_url()).await;
        let models = probe_get(&client, &self.config.llama_models_url()).await;
        health.get("ok").and_then(Value::as_bool).unwrap_or(false)
            && models.get("ok").and_then(Value::as_bool).unwrap_or(false)
    }

    async fn wait_existing_listener_ready(&self) -> bool {
        let deadline = Instant::now() + self.config.health_timeout();
        while Instant::now() < deadline {
            if self.existing_listener_ready().await {
                return true;
            }
            sleep(Duration::from_secs(1)).await;
        }
        false
    }
}

pub async fn probe_runtime(config: &ServerConfig) -> Result<Value> {
    let client = reqwest::Client::new();
    let health = probe_get(&client, &config.llama_health_url()).await;
    let models = probe_get(&client, &config.llama_models_url()).await;
    let chat = probe_chat(
        &client,
        &config.llama_base_url,
        config.direct_smoke_timeout(),
    )
    .await;
    Ok(json!({
        "health": health,
        "models": models,
        "chat": chat,
        "runtime_ready": health.get("ok").and_then(Value::as_bool).unwrap_or(false)
            && models.get("ok").and_then(Value::as_bool).unwrap_or(false)
            && chat.get("ok").and_then(Value::as_bool).unwrap_or(false),
    }))
}

async fn probe_get(client: &reqwest::Client, url: &str) -> Value {
    match client.get(url).timeout(Duration::from_secs(5)).send().await {
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
    }
}

async fn post_chat_payload(
    client: &reqwest::Client,
    url: &str,
    payload: Value,
    budget: Duration,
) -> std::result::Result<Value, LlamaChatError> {
    let result = timeout(budget, async {
        let response = client
            .post(url)
            .json(&payload)
            .send()
            .await
            .map_err(|err| LlamaChatError::Request(err.to_string()))?;
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        if !status.is_success() {
            return Err(LlamaChatError::Http {
                status: status.as_u16(),
                body,
            });
        }
        serde_json::from_str::<Value>(&body)
            .map_err(|err| LlamaChatError::InvalidResponse(err.to_string()))
    })
    .await;

    match result {
        Ok(value) => value,
        Err(_) => Err(LlamaChatError::Timeout {
            timeout_s: budget.as_secs(),
        }),
    }
}

async fn probe_chat(client: &reqwest::Client, base_url: &str, budget: Duration) -> Value {
    let url = format!("{}/chat/completions", base_url.trim_end_matches('/'));
    let payload = json!({
        "messages": [{"role": "user", "content": "Reply with exactly: HEARTH_RUNTIME_PROBE"}],
        "max_tokens": 16,
        "temperature": 0.0,
        "chat_template_kwargs": {
            "enable_thinking": false,
        },
    });
    match post_chat_payload(client, &url, payload, budget).await {
        Ok(body) => {
            let valid_completion = body
                .get("choices")
                .and_then(Value::as_array)
                .is_some_and(|choices| !choices.is_empty());
            json!({
                "ok": valid_completion,
                "status": 200,
                "url": url,
                "matched_probe": body.to_string().contains("HEARTH_RUNTIME_PROBE"),
                "valid_completion": valid_completion,
            })
        }
        Err(err) => json!({
            "ok": false,
            "url": url,
            "error": err.to_string(),
        }),
    }
}
