mod assets;
mod comfyui;
mod config;
mod llama;
mod models;
mod persona;
mod protocol;
mod ws;

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Instant;

use anyhow::{Context, Result};
use comfyui::ComfyUISupervisor;
use config::ServerConfig;
use llama::LlamaSupervisor;
use persona::PersonaStore;
use tokio::net::TcpListener;
use tokio::sync::Mutex;
use tracing::{info, warn};
use tracing_subscriber::EnvFilter;

#[derive(Clone)]
pub struct AppState {
    pub config: ServerConfig,
    pub personas: PersonaStore,
    pub llama: Arc<Mutex<LlamaSupervisor>>,
    pub comfy: Arc<Mutex<ComfyUISupervisor>>,
    pub started_at: Instant,
    pub current_persona: Arc<Mutex<String>>,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("info".parse()?))
        .init();

    let config = ServerConfig::from_env()?;
    let print_config = std::env::args().any(|arg| arg == "--print-config");
    let probe_runtime = std::env::args().any(|arg| arg == "--probe-runtime");
    if probe_runtime {
        let diagnostics = llama::probe_runtime(&config).await?;
        println!("{}", serde_json::to_string_pretty(&diagnostics)?);
        return Ok(());
    }
    if config.dry_run || print_config {
        print_dry_run(&config)?;
        return Ok(());
    }

    let personas = PersonaStore::new(
        config.repo_root.clone(),
        &config.asset_host,
        config.asset_port,
    );
    let active_persona = personas
        .get(&config.active_persona)
        .with_context(|| format!("load active persona {}", config.active_persona))?;

    let mut llama = LlamaSupervisor::new(config.clone());
    tokio::select! {
        result = llama.ensure_started_for(&active_persona) => {
            // The brain is the reason this process exists; a failure to make the
            // active persona's model resident is fatal rather than a warning.
            // (Before 2026-08-04 this was only fatal when the OpenCode harness
            // flag was set, which was the default, so this preserves behaviour.)
            result.context("llama-server readiness failed")?;
        }
        _ = tokio::signal::ctrl_c() => {
            info!("shutdown requested during llama-server startup");
            llama.stop().await;
            return Ok(());
        }
    }

    // ComfyUI is best-effort at boot: a missing COMFYUI_PATH or unreachable port
    // should not block the rest of the harness. The first /comfy/submit call
    // will surface the error to its caller.
    let mut comfy = ComfyUISupervisor::new(config.clone());
    if config.comfy_path.is_some() || config.comfy_external {
        match comfy.ensure_started().await {
            Ok(()) => info!("ComfyUI supervisor ready"),
            Err(err) => warn!("ComfyUI supervisor not ready (will retry on first job): {}", err),
        }
    } else {
        info!("ComfyUI supervisor inactive: set COMFYUI_PATH or COMFYUI_EXTERNAL=1 to enable");
    }

    let state = AppState {
        personas,
        llama: Arc::new(Mutex::new(llama)),
        comfy: Arc::new(Mutex::new(comfy)),
        started_at: Instant::now(),
        current_persona: Arc::new(Mutex::new(config.active_persona.clone())),
        config: config.clone(),
    };

    spawn_stuck_slot_watchdog(state.llama.clone(), config.direct_chat_timeout_s);
    spawn_comfy_stuck_job_watchdog(state.comfy.clone(), config.comfy_job_timeout_s);

    let ws_addr: SocketAddr = format!("{}:{}", config.websocket_host, config.websocket_port)
        .parse()
        .context("parse websocket listen address")?;
    let asset_addr: SocketAddr = format!("{}:{}", config.asset_host, config.asset_port)
        .parse()
        .context("parse asset listen address")?;

    let ws_listener = TcpListener::bind(ws_addr).await?;
    let asset_listener = TcpListener::bind(asset_addr).await?;
    info!("websocket server listening on {}", ws_addr);
    info!("asset server listening on {}", asset_addr);

    let ws_server = axum::serve(ws_listener, ws::router(state.clone()));
    let asset_server = axum::serve(asset_listener, assets::router(state.clone()));

    tokio::select! {
        result = ws_server => result.context("websocket server")?,
        result = asset_server => result.context("asset server")?,
        _ = tokio::signal::ctrl_c() => {
            info!("shutdown requested");
        }
    }

    state.llama.lock().await.stop().await;
    state.comfy.lock().await.stop().await;
    Ok(())
}

/// Background watchdog that force-restarts ComfyUI when a /comfy/submit
/// stays in flight past `2 * comfy_job_timeout_s`. ComfyUI's queue can wedge
/// on CUDA OOM in ways the HTTP timeout alone doesn't clear.
fn spawn_comfy_stuck_job_watchdog(comfy: Arc<Mutex<ComfyUISupervisor>>, comfy_job_timeout_s: u64) {
    let limit = std::time::Duration::from_secs(comfy_job_timeout_s.saturating_mul(2).max(120));
    let poll = std::time::Duration::from_secs(10);
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(poll).await;
            let Ok(mut guard) = comfy.try_lock() else {
                continue;
            };
            if let Some(in_flight_for) = guard.job_in_flight_since() {
                if in_flight_for > limit {
                    warn!(
                        "stuck-slot watchdog: comfy job in flight for {:?} (limit {:?}); force-restarting",
                        in_flight_for, limit
                    );
                    let _ = guard.force_restart().await;
                }
            }
        }
    });
}

/// Background watchdog that force-restarts the supervised llama-server when
/// an in-flight chat outlives `2 * direct_chat_timeout`. Per-call timeouts
/// inside `post_chat_completion` are the first line of defence; this guards
/// the residual case where the timeout fires but the slot is still wedged.
fn spawn_stuck_slot_watchdog(
    llama: Arc<Mutex<LlamaSupervisor>>,
    direct_chat_timeout_s: u64,
) {
    let limit = std::time::Duration::from_secs(direct_chat_timeout_s.saturating_mul(2).max(60));
    let poll = std::time::Duration::from_secs(5);
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(poll).await;
            // try_lock so we never block the supervisor; if a real call holds
            // the lock its own timeout still applies. We only intervene when
            // the lock frees but the stale `chat_started_at` says a slot
            // wedged past the in-flight call returning.
            let Ok(mut guard) = llama.try_lock() else {
                continue;
            };
            if let Some(in_flight_for) = guard.chat_in_flight_since() {
                if in_flight_for > limit {
                    warn!(
                        "stuck-slot watchdog: chat in flight for {:?} (limit {:?}); force-restarting",
                        in_flight_for, limit
                    );
                    let _ = guard.force_restart().await;
                }
            }
        }
    });
}

fn print_dry_run(config: &ServerConfig) -> Result<()> {
    let personas = PersonaStore::new(
        config.repo_root.clone(),
        &config.asset_host,
        config.asset_port,
    );
    let persona_result = personas.get(&config.active_persona);
    let persona_ok = persona_result.is_ok();
    let llama_bin_ok = config.llama_server_bin.exists();

    let diagnostics = serde_json::json!({
        "repo_root": config.repo_root,
        "active_persona": config.active_persona,
        "websocket": {"host": config.websocket_host, "port": config.websocket_port},
        "assets": {"host": config.asset_host, "port": config.asset_port},
        "pty_port": config.pty_port,
        "llama": {
            "host": config.llama_host,
            "port": config.llama_port,
            "base_url": config.llama_base_url,
            "health_url": config.llama_health_url(),
            "models_url": config.llama_models_url(),
            "server_bin": config.llama_server_bin,
            "server_bin_exists": llama_bin_ok,
            "kv_cache_type": config.kv_cache_type,
            "parallel": config.llama_parallel,
            "no_warmup": config.llama_no_warmup,
            "reasoning": config.llama_reasoning,
            "cuda_unified_memory": {
                "enabled": config.llama_cuda_unified_memory,
                "child_env": "GGML_CUDA_ENABLE_UNIFIED_MEMORY=1 when enabled (see HEARTH_LLAMA_CUDA_UNIFIED_MEMORY)"
            },
            "health_timeout_s": config.llama_health_timeout_s,
            "direct_chat_timeout_s": config.direct_chat_timeout_s,
            "direct_smoke_timeout_s": config.direct_smoke_timeout_s,
            "generic_llm_max_input_chars": config.generic_llm_max_input_chars,
            "generic_llm_max_output_tokens": config.generic_llm_max_output_tokens,
            "runtime_probe_command": "scripts/supervisor_run.sh --probe-runtime"
        },
        "comfyui": {
            "host": config.comfy_host,
            "port": config.comfy_port,
            "base_url": config.comfy_base_url(),
            "system_stats_url": config.comfy_system_stats_url(),
            "path": config.comfy_path.as_ref().map(|p| p.display().to_string()),
            "external": config.comfy_external,
            "health_timeout_s": config.comfy_health_timeout_s,
            "submit_timeout_s": config.comfy_submit_timeout_s,
            "job_timeout_s": config.comfy_job_timeout_s,
            "active": config.comfy_path.is_some() || config.comfy_external
        },
        "persona_loaded": persona_ok,
        "runtime_ready": llama_bin_ok && persona_ok
    });
    println!("{}", serde_json::to_string_pretty(&diagnostics)?);
    if !llama_bin_ok {
        warn!(
            "WSL-native llama-server is missing at {}",
            config.llama_server_bin.display()
        );
    }
    Ok(())
}
