use std::env;
use std::path::{Path, PathBuf};
use std::time::Duration;

use anyhow::{Context, Result};
use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct ServerConfig {
    pub repo_root: PathBuf,
    pub workspace_root: PathBuf,
    pub project_slug: String,
    pub active_persona: String,
    pub websocket_host: String,
    pub websocket_port: u16,
    pub asset_host: String,
    pub asset_port: u16,
    pub pty_port: u16,
    pub llama_host: String,
    pub llama_port: u16,
    pub llama_base_url: String,
    pub llama_server_bin: PathBuf,
    pub kv_cache_type: String,
    pub llama_parallel: u16,
    pub llama_ctx_override: Option<u64>,
    pub llama_no_warmup: bool,
    /// When true, `llama-server` is started with `GGML_CUDA_ENABLE_UNIFIED_MEMORY=1` (see llama.cpp / GGML CUDA docs).
    pub llama_cuda_unified_memory: bool,
    pub llama_reasoning: String,
    pub llama_health_timeout_s: u64,
    pub direct_chat_timeout_s: u64,
    pub direct_smoke_timeout_s: u64,
    pub generic_llm_max_input_chars: u64,
    pub generic_llm_max_output_tokens: u64,
    /// Path to the speculative-decoding draft model (e.g. Qwen3-1.7B-Q4_K_M.gguf).
    /// When set, llama-server is started with --spec-draft-model and related flags.
    pub spec_draft_model: Option<PathBuf>,
    pub dry_run: bool,
    pub python_bin: String,
    pub mentat_worker_enabled: bool,
    // --- ComfyUI harness (engram_comfy) ---
    pub comfy_host: String,
    pub comfy_port: u16,
    /// Filesystem path to a ComfyUI checkout (the directory containing main.py).
    /// When None, the supervisor refuses to spawn; set COMFYUI_EXTERNAL=1 to adopt
    /// an externally launched instance instead.
    pub comfy_path: Option<PathBuf>,
    pub comfy_python: PathBuf,
    pub comfy_external: bool,
    pub comfy_health_timeout_s: u64,
    pub comfy_submit_timeout_s: u64,
    pub comfy_job_timeout_s: u64,
    /// Extra space-separated args appended to `python main.py --listen ... --port ...`.
    pub comfy_extra_args: Option<String>,
}

impl ServerConfig {
    pub fn from_env() -> Result<Self> {
        let repo_root = normalize_path(&env_or("HEARTH_ROOT", "/mnt/d/Tools/Valinor"));
        let workspace_root = normalize_path(&env_or(
            "HEARTH_MENTAT_WORKSPACE_ROOT",
            "/mnt/d/Tools/mentat-workspace",
        ));
        let project_slug = env_or("HEARTH_MENTAT_PROJECT_SLUG", "valinor-webapp");
        let active_persona = env_or("HEARTH_DEEPAGENT_PERSONA", "Mentat");
        let websocket_host = env_or("HEARTH_RUST_WS_HOST", "0.0.0.0");
        let websocket_port = env_u16("HEARTH_RUST_WS_PORT", 8765)?;
        let asset_host = env_or("HEARTH_RUST_ASSET_HOST", "0.0.0.0");
        let asset_port = env_u16("HEARTH_RUST_ASSET_PORT", 8766)?;
        let pty_port = env_u16("HEARTH_PTY_PORT", 8767)?;
        let llama_host = env_or("HEARTH_LLAMA_HOST", "127.0.0.1");
        let llama_port = env_u16("HEARTH_LLAMA_PORT", 8080)?;
        let llama_base_url = env::var("HEARTH_LLAMA_BASE_URL")
            .ok()
            .filter(|v| !v.trim().is_empty())
            .unwrap_or_else(|| format!("http://{}:{}/v1", llama_host, llama_port));
        let llama_server_bin = normalize_path(&env_or(
            "HEARTH_LLAMA_SERVER_BIN",
            "/usr/local/bin/llama-server",
        ));
        let kv_cache_type = env_or("HEARTH_KV_CACHE_TYPE", "q4_0");
        let llama_parallel = env_u16("HEARTH_LLAMA_PARALLEL", 1)?;
        let llama_ctx_override = env_optional_u64("HEARTH_LLAMA_CTX")?;
        let llama_no_warmup = env_flag("HEARTH_LLAMA_NO_WARMUP", true);
        // Default off when not using the WSL launch script; `supervisor_run.sh` sets 1.
        let llama_cuda_unified_memory = env_flag("HEARTH_LLAMA_CUDA_UNIFIED_MEMORY", false);
        let llama_reasoning = env_enum("HEARTH_LLAMA_REASONING", "off", &["on", "off", "auto"])?;
        let llama_health_timeout_s = env_u64("HEARTH_LLAMA_HEALTH_TIMEOUT_S", 300)?;
        // Innermost timeout: wraps the generation POST to llama-server. Must be
        // large enough for a heavy/`/deep` 35B turn to finish, and stay under the
        // gateway's CHAT_TIMEOUT_S (360s) and the bot's read timeout (390s). The
        // stuck-slot watchdog backstop is 2x this value (see main.rs).
        let direct_chat_timeout_s = env_u64("HEARTH_RUST_DIRECT_TIMEOUT_S", 240)?;
        let direct_smoke_timeout_s = env_u64("HEARTH_RUST_DIRECT_SMOKE_TIMEOUT_S", 20)?;
        let generic_llm_max_input_chars = env_u64("HEARTH_RUST_GENERIC_MAX_INPUT_CHARS", 24_000)?;
        let generic_llm_max_output_tokens = env_u64("HEARTH_RUST_GENERIC_MAX_TOKENS", 512)?;
        let spec_draft_model = env::var("HEARTH_SPEC_DRAFT_MODEL")
            .ok()
            .filter(|v| !v.trim().is_empty())
            .map(|v| normalize_path(v.trim()))
            .filter(|p| p.exists());
        let dry_run = env_flag("HEARTH_RUST_DRY_RUN", false);
        let python_bin = env_or("HEARTH_RUST_PYTHON_BIN", "python3");
        let mentat_worker_enabled = env_flag("HEARTH_RUST_MENTAT_WORKER", true);

        let comfy_host = env_or("COMFYUI_HOST", "127.0.0.1");
        let comfy_port = env_u16("COMFYUI_PORT", 8188)?;
        let comfy_path = env::var("COMFYUI_PATH")
            .ok()
            .filter(|v| !v.trim().is_empty())
            .map(|v| normalize_path(v.trim()));
        let comfy_python = normalize_path(&env_or("COMFYUI_PYTHON", "python3"));
        let comfy_external = env_flag("COMFYUI_EXTERNAL", false);
        let comfy_health_timeout_s = env_u64("COMFYUI_HEALTH_TIMEOUT_S", 300)?;
        let comfy_submit_timeout_s = env_u64("COMFYUI_SUBMIT_TIMEOUT_S", 30)?;
        let comfy_job_timeout_s = env_u64("COMFYUI_JOB_TIMEOUT_S", 600)?;
        let comfy_extra_args = env::var("COMFYUI_EXTRA_ARGS")
            .ok()
            .filter(|v| !v.trim().is_empty());

        Ok(Self {
            repo_root,
            workspace_root,
            project_slug,
            active_persona,
            websocket_host,
            websocket_port,
            asset_host,
            asset_port,
            pty_port,
            llama_host,
            llama_port,
            llama_base_url,
            llama_server_bin,
            kv_cache_type,
            llama_parallel,
            llama_ctx_override,
            llama_no_warmup,
            llama_cuda_unified_memory,
            llama_reasoning,
            llama_health_timeout_s,
            direct_chat_timeout_s,
            direct_smoke_timeout_s,
            generic_llm_max_input_chars,
            generic_llm_max_output_tokens,
            spec_draft_model,
            dry_run,
            python_bin,
            mentat_worker_enabled,
            comfy_host,
            comfy_port,
            comfy_path,
            comfy_python,
            comfy_external,
            comfy_health_timeout_s,
            comfy_submit_timeout_s,
            comfy_job_timeout_s,
            comfy_extra_args,
        })
    }

    pub fn comfy_base_url(&self) -> String {
        format!("http://{}:{}", self.comfy_host, self.comfy_port)
    }

    pub fn comfy_system_stats_url(&self) -> String {
        format!("{}/system_stats", self.comfy_base_url())
    }

    pub fn comfy_ws_url(&self, client_id: &str) -> String {
        format!(
            "ws://{}:{}/ws?clientId={}",
            self.comfy_host, self.comfy_port, client_id
        )
    }

    pub fn comfy_health_timeout(&self) -> Duration {
        Duration::from_secs(self.comfy_health_timeout_s)
    }

    pub fn comfy_submit_timeout(&self) -> Duration {
        Duration::from_secs(self.comfy_submit_timeout_s)
    }

    pub fn comfy_job_timeout(&self) -> Duration {
        Duration::from_secs(self.comfy_job_timeout_s)
    }

    pub fn llama_health_url(&self) -> String {
        format!("http://{}:{}/health", self.llama_host, self.llama_port)
    }

    pub fn llama_models_url(&self) -> String {
        format!("http://{}:{}/v1/models", self.llama_host, self.llama_port)
    }

    pub fn log_dir(&self) -> PathBuf {
        self.repo_root.join(".hearth").join("logs")
    }

    pub fn worker_path(&self) -> PathBuf {
        self.repo_root
            .join("Server")
            .join("agents")
            .join("mentat_worker_stdio.py")
    }

    pub fn health_timeout(&self) -> Duration {
        Duration::from_secs(self.llama_health_timeout_s)
    }

    pub fn direct_chat_timeout(&self) -> Duration {
        Duration::from_secs(self.direct_chat_timeout_s)
    }

    pub fn direct_smoke_timeout(&self) -> Duration {
        Duration::from_secs(self.direct_smoke_timeout_s)
    }

}

pub fn normalize_path(value: &str) -> PathBuf {
    let trimmed = value.trim().replace('\\', "/");
    let bytes = trimmed.as_bytes();
    if bytes.len() >= 2 && bytes[1] == b':' {
        let drive = (bytes[0] as char).to_ascii_lowercase();
        let rest = trimmed[2..].trim_start_matches('/');
        return PathBuf::from(format!("/mnt/{}/{}", drive, rest));
    }
    PathBuf::from(trimmed)
}

pub fn resolve_repo_path(repo_root: &Path, value: &str) -> PathBuf {
    let path = normalize_path(value);
    if path.is_absolute() {
        path
    } else {
        repo_root.join(path)
    }
}

fn env_or(name: &str, default: &str) -> String {
    env::var(name)
        .ok()
        .filter(|v| !v.trim().is_empty())
        .unwrap_or_else(|| default.to_string())
}

fn env_flag(name: &str, default: bool) -> bool {
    match env::var(name) {
        Ok(value) => match value.trim().to_ascii_lowercase().as_str() {
            "1" | "true" | "yes" | "on" => true,
            "0" | "false" | "no" | "off" => false,
            _ => default,
        },
        Err(_) => default,
    }
}

fn env_enum(name: &str, default: &str, allowed: &[&str]) -> Result<String> {
    let value = env::var(name).unwrap_or_else(|_| default.to_string());
    let value = value.trim().to_ascii_lowercase();
    if allowed.iter().any(|allowed| *allowed == value) {
        Ok(value)
    } else {
        Err(anyhow::anyhow!(
            "{} must be one of {}; got {}",
            name,
            allowed.join(", "),
            value
        ))
    }
}

fn env_u16(name: &str, default: u16) -> Result<u16> {
    match env::var(name) {
        Ok(value) if !value.trim().is_empty() => value
            .trim()
            .parse::<u16>()
            .with_context(|| format!("invalid integer in {}", name)),
        _ => Ok(default),
    }
}

fn env_u64(name: &str, default: u64) -> Result<u64> {
    match env::var(name) {
        Ok(value) if !value.trim().is_empty() => value
            .trim()
            .parse::<u64>()
            .with_context(|| format!("invalid integer in {}", name)),
        _ => Ok(default),
    }
}

fn env_optional_u64(name: &str) -> Result<Option<u64>> {
    match env::var(name) {
        Ok(value) if !value.trim().is_empty() => value
            .trim()
            .parse::<u64>()
            .map(Some)
            .with_context(|| format!("invalid integer in {}", name)),
        _ => Ok(None),
    }
}
