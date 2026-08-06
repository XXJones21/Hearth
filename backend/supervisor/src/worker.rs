use std::process::Stdio;
use std::sync::Arc;

use anyhow::{anyhow, Context, Result};
use axum::extract::ws::{Message, WebSocket};
use serde_json::{json, Value};
use tokio::fs::OpenOptions;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::Command;
use tokio::sync::Mutex;
use tracing::warn;

use crate::config::ServerConfig;
use crate::protocol::{now_timestamp, AiResponse, PipelineStage};

pub async fn run_mentat_turn(
    socket: &mut WebSocket,
    config: &ServerConfig,
    text: &str,
    session_id: &str,
    persona_name: &str,
) -> Result<()> {
    std::fs::create_dir_all(config.log_dir())?;
    let stderr_tail = Arc::new(Mutex::new(Vec::<String>::new()));
    let mut child = Command::new(&config.python_bin)
        .arg(config.worker_path())
        .current_dir(&config.repo_root)
        .env("HEARTH_LLAMA_BASE_URL", &config.llama_base_url)
        .env("HEARTH_MENTAT_WORKSPACE_ROOT", &config.workspace_root)
        .env("HEARTH_MENTAT_PROJECT_SLUG", &config.project_slug)
        .env("HEARTH_MENTAT_MODE", "agent")
        .env("HEARTH_MENTAT_HARNESS", "hermes")
        .env("HEARTH_STACK_SERVER", "rust")
        .env("PYTHONUNBUFFERED", "1")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("spawn Mentat worker")?;

    let mut stdin = child.stdin.take().context("worker stdin unavailable")?;
    let stdout = child.stdout.take().context("worker stdout unavailable")?;
    let stderr = child.stderr.take().context("worker stderr unavailable")?;
    let stderr_log = config.log_dir().join("mentat-worker.err.log");
    let stderr_tail_task = Arc::clone(&stderr_tail);
    let stderr_task = tokio::spawn(async move {
        let mut log = OpenOptions::new()
            .create(true)
            .append(true)
            .open(stderr_log)
            .await
            .ok();
        let mut lines = BufReader::new(stderr).lines();
        while let Ok(Some(line)) = lines.next_line().await {
            if !line.trim().is_empty() {
                warn!("Mentat worker stderr: {}", line);
                if let Some(file) = log.as_mut() {
                    let _ = file.write_all(line.as_bytes()).await;
                    let _ = file.write_all(b"\n").await;
                }
                let mut tail = stderr_tail_task.lock().await;
                tail.push(line);
                if tail.len() > 20 {
                    tail.remove(0);
                }
            }
        }
    });
    let request = json!({
        "text": text,
        "session_id": session_id,
        "user_id": "user_001",
        "persona_name": persona_name,
        "project_slug": config.project_slug,
        "workspace_root": config.workspace_root,
        "llama_base_url": config.llama_base_url,
        "stack_server": "rust",
    });
    stdin
        .write_all(serde_json::to_string(&request)?.as_bytes())
        .await?;
    stdin.write_all(b"\n").await?;
    drop(stdin);

    let mut lines = BufReader::new(stdout).lines();
    let mut final_response: Option<String> = None;
    let mut execute_artifacts: Option<Value> = None;
    let mut worker_error: Option<String> = None;
    while let Some(line) = lines.next_line().await? {
        if line.trim().is_empty() {
            continue;
        }
        let record: Value =
            serde_json::from_str(&line).with_context(|| format!("parse worker line: {}", line))?;
        match record.get("type").and_then(Value::as_str) {
            Some("stage") => {
                let stage = record
                    .get("stage")
                    .and_then(Value::as_str)
                    .unwrap_or("mentat_agent")
                    .to_string();
                let event = record
                    .get("event")
                    .and_then(Value::as_str)
                    .unwrap_or("event")
                    .to_string();
                let data = record.get("data").cloned().unwrap_or_else(|| json!({}));
                send_json(
                    socket,
                    &PipelineStage {
                        action: "pipeline_stage",
                        stage,
                        event,
                        timestamp: now_timestamp(),
                        data,
                    },
                )
                .await?;
            }
            Some("result") => {
                final_response = record
                    .get("final_response")
                    .and_then(Value::as_str)
                    .map(ToOwned::to_owned);
                execute_artifacts = artifact_payload(&record, persona_name);
            }
            Some("execute_artifacts") => {
                let mut payload = record.clone();
                if let Some(object) = payload.as_object_mut() {
                    object.remove("type");
                    object
                        .entry("timestamp")
                        .or_insert_with(|| Value::String(now_timestamp()));
                }
                execute_artifacts = Some(payload);
            }
            Some("error") => {
                let detail = record
                    .get("detail")
                    .and_then(Value::as_str)
                    .unwrap_or("worker error");
                worker_error = Some(detail.to_string());
                break;
            }
            _ => {}
        }
    }

    let status = child.wait().await?;
    let _ = stderr_task.await;
    let stderr_tail_text = stderr_tail.lock().await.join("\n");
    if let Some(detail) = worker_error {
        if stderr_tail_text.is_empty() {
            return Err(anyhow!(detail));
        }
        return Err(anyhow!(
            "{}; worker stderr tail: {}",
            detail,
            stderr_tail_text
        ));
    }
    if !status.success() {
        if stderr_tail_text.is_empty() {
            return Err(anyhow!("Mentat worker exited with {}", status));
        }
        return Err(anyhow!(
            "Mentat worker exited with {}; stderr tail: {}",
            status,
            stderr_tail_text
        ));
    }

    let text = final_response
        .unwrap_or_else(|| "Mentat worker completed without a final response.".to_string());
    send_json(
        socket,
        &AiResponse {
            action: "ai_response",
            text,
            persona_name: persona_name.to_string(),
            has_audio: false,
            intent: "coding".to_string(),
            model_used: "deep".to_string(),
            session_id: session_id.to_string(),
            timestamp: now_timestamp(),
        },
    )
    .await?;

    if let Some(artifacts) = execute_artifacts {
        send_json(socket, &artifacts).await?;
    }

    Ok(())
}

async fn send_json<T: serde::Serialize>(socket: &mut WebSocket, value: &T) -> Result<()> {
    let raw = serde_json::to_string(value)?;
    socket.send(Message::Text(raw)).await?;
    Ok(())
}

fn artifact_payload(record: &Value, persona_name: &str) -> Option<Value> {
    let raw = record.get("raw")?;
    let session_log = raw.get("session_log").and_then(Value::as_str)?;
    if session_log.trim().is_empty() {
        return None;
    }
    Some(json!({
        "action": "execute_artifacts",
        "intent": "coding",
        "file_path": Value::Null,
        "code_artifacts": [{
            "ok": true,
            "file_path": session_log,
            "lines": raw.get("steps_taken").and_then(Value::as_u64).unwrap_or(0),
            "language": "jsonl",
            "role": "session_log",
            "persona_name": persona_name,
        }],
        "timestamp": now_timestamp(),
    }))
}
