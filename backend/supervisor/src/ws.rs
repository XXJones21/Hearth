use anyhow::Result;
use axum::body::Body;
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{Json, Path, Query, State};
use axum::http::{HeaderValue, Response, StatusCode};
use axum::response::IntoResponse;
use axum::routing::{get, post};
use axum::Router;
use futures_util::StreamExt;
use serde::Serialize;
use serde_json::{json, Value};
use std::sync::atomic::{AtomicBool, Ordering};
use tower_http::cors::{Any, CorsLayer};
use tracing::{info, warn};
use uuid::Uuid;

// Logs the WS text_query deprecation once per server boot. Phase 5 (2026-05-10):
// the Hermes gateway sidecar at 127.0.0.1:8770 is the recommended entry point
// for chat completions. The WS text_query handler stays functional so existing
// F1 (`llm_review.py` via `valinor_ws` provider) and the desktop client keep
// working; this is a soft deprecation only.
static TEXT_QUERY_DEPRECATION_LOGGED: AtomicBool = AtomicBool::new(false);

use crate::comfyui::ComfyError;
use crate::config::ServerConfig;
use crate::llama::LlamaChatError;
use crate::protocol::{
    now_timestamp, AiResponse, ClientCommand, ClientInfoAck, ErrorMessage, PersonaConfig,
    PersonaList, PersonaSwitched, PingResponse, PipelineStage, ServerCapabilities,
};
use crate::AppState;

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/", get(ws_handler))
        .route("/ws", get(ws_handler))
        .route("/v1/chat/completions", post(llm_chat_completions))
        .route("/llm/chat/completions", post(llm_chat_completions))
        .route("/comfy/submit", post(comfy_submit))
        .route("/comfy/history/:prompt_id", get(comfy_history))
        .route("/comfy/asset/:filename", get(comfy_asset))
        .route("/comfy/stream/:prompt_id", get(comfy_stream))
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any),
        )
        .with_state(state)
}

async fn ws_handler(ws: WebSocketUpgrade, State(state): State<AppState>) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, state))
}

async fn llm_chat_completions(
    State(state): State<AppState>,
    Json(payload): Json<Value>,
) -> impl IntoResponse {
    let payload = match prepare_generic_llm_payload(&state.config, payload) {
        Ok(payload) => payload,
        Err((status, body)) => return (status, Json(body)).into_response(),
    };
    match state.llama.lock().await.chat_completion_raw(payload).await {
        Ok(completion) => (StatusCode::OK, Json(completion.body)).into_response(),
        Err(err) => {
            let status = match &err {
                LlamaChatError::Timeout { .. } => StatusCode::GATEWAY_TIMEOUT,
                LlamaChatError::Request(_) | LlamaChatError::InvalidResponse(_) => {
                    StatusCode::BAD_GATEWAY
                }
                LlamaChatError::Http { status, .. } => {
                    StatusCode::from_u16(*status).unwrap_or(StatusCode::BAD_GATEWAY)
                }
                LlamaChatError::ExternalDirty { .. } | LlamaChatError::RestartFailed { .. } => {
                    StatusCode::SERVICE_UNAVAILABLE
                }
            };
            (
                status,
                Json(json!({
                    "error": {
                        "kind": err.kind(),
                        "message": err.to_string(),
                    }
                })),
            )
                .into_response()
        }
    }
}

fn prepare_generic_llm_payload(
    config: &ServerConfig,
    mut payload: Value,
) -> std::result::Result<Value, (StatusCode, Value)> {
    let payload_chars = payload.to_string().chars().count() as u64;
    if payload_chars > config.generic_llm_max_input_chars {
        return Err((
            StatusCode::PAYLOAD_TOO_LARGE,
            json!({
                "error": {
                    "kind": "input_too_large",
                    "message": format!(
                        "generic LLM request is {} chars; limit is {} chars",
                        payload_chars, config.generic_llm_max_input_chars
                    ),
                }
            }),
        ));
    }

    let Some(object) = payload.as_object_mut() else {
        return Err((
            StatusCode::BAD_REQUEST,
            json!({
                "error": {
                    "kind": "invalid_payload",
                    "message": "generic LLM request body must be a JSON object",
                }
            }),
        ));
    };

    object.insert("stream".to_string(), json!(false));
    let requested_max_tokens = object
        .get("max_tokens")
        .or_else(|| object.get("n_predict"))
        .and_then(Value::as_u64)
        .unwrap_or(config.generic_llm_max_output_tokens);
    let max_tokens = requested_max_tokens.min(config.generic_llm_max_output_tokens);
    object.insert("max_tokens".to_string(), json!(max_tokens));
    object.insert("n_predict".to_string(), json!(max_tokens));

    let template_kwargs = object
        .entry("chat_template_kwargs")
        .or_insert_with(|| json!({}));
    if let Some(template_object) = template_kwargs.as_object_mut() {
        template_object.insert("enable_thinking".to_string(), json!(false));
    }

    Ok(payload)
}

async fn handle_socket(mut socket: WebSocket, state: AppState) {
    let session_id = Uuid::new_v4().to_string();
    while let Some(Ok(message)) = socket.next().await {
        let Message::Text(raw) = message else {
            continue;
        };
        let parsed = serde_json::from_str::<ClientCommand>(&raw);
        let command = match parsed {
            Ok(command) => command,
            Err(err) => {
                let _ = send_json(
                    &mut socket,
                    &ErrorMessage {
                        action: "error",
                        message: format!("invalid command JSON: {}", err),
                    },
                )
                .await;
                continue;
            }
        };
        if let Err(err) = handle_command(&mut socket, &state, &session_id, command).await {
            let _ = send_json(
                &mut socket,
                &ErrorMessage {
                    action: "error",
                    message: err.to_string(),
                },
            )
            .await;
        }
    }
}

async fn handle_command(
    socket: &mut WebSocket,
    state: &AppState,
    session_id: &str,
    command: ClientCommand,
) -> Result<()> {
    match command.action.as_str() {
        "client_info" => {
            let _platform = command.platform.unwrap_or_else(|| "desktop".to_string());
            let _capabilities = command.capabilities;
            send_json(
                socket,
                &ClientInfoAck {
                    action: "client_info_ack",
                    status: "received",
                    server_capabilities: ServerCapabilities {
                        audio_generation: false,
                        voice_cloning: false,
                        spatial_support: false,
                    },
                },
            )
            .await?;
        }
        "list_personas" => {
            let personas = state.personas.list()?;
            let current_persona = state.current_persona.lock().await.clone();
            send_json(
                socket,
                &PersonaList {
                    action: "personas_list",
                    personas,
                    current_persona,
                },
            )
            .await?;
        }
        "get_persona_config" => {
            let Some(persona_name) = command.persona_name else {
                anyhow::bail!("get_persona_config requires persona_name");
            };
            let config = state.personas.get(&persona_name)?;
            send_json(
                socket,
                &PersonaConfig {
                    action: "persona_config",
                    persona_name,
                    config,
                },
            )
            .await?;
        }
        "switch_persona" => {
            let Some(persona_name) = command.persona_name else {
                anyhow::bail!("switch_persona requires persona_name");
            };
            let config = state.personas.get(&persona_name)?;
            // Always check model spec. For same-class switches (e.g. Sulivan → Selene) this is a
            // no-op. For cross-class switches (Mentat 27B ↔ Sulivan/Selene 35B-A3B) it kills and
            // reloads llama-server. The call blocks until the new model is ready (~60–180 s for a
            // cross-class swap on an RTX 4080).
            state.llama.lock().await.ensure_started_for(&config).await?;
            *state.current_persona.lock().await = persona_name.clone();
            send_json(
                socket,
                &PersonaSwitched {
                    action: "persona_switched",
                    persona_name,
                    status: "success",
                },
            )
            .await?;
        }
        "ping" => {
            let uptime_s = state.started_at.elapsed().as_secs();
            let current_persona = state.current_persona.lock().await.clone();
            let (llama_ready, active_model) = {
                let mut llama = state.llama.lock().await;
                let ready = llama.is_ready().await;
                let active_model = llama.active_model_label();
                (ready, active_model)
            };
            send_json(
                socket,
                &PingResponse {
                    action: "pong",
                    status: "ok",
                    uptime_s,
                    current_persona,
                    llama_ready,
                    active_model,
                },
            )
            .await?;
        }
        "text_query" => {
            // DEPRECATED (2026-05-10): use the Hermes gateway sidecar at
            // 127.0.0.1:8770 (POST /v1/chat/completions) for new clients.
            // This handler stays for backward compatibility with F1 (valinor_ws
            // provider) and the desktop WS client. See
            // wiki/architecture/harness/hermes-gateway-sidecar.md for the
            // migration path.
            if !TEXT_QUERY_DEPRECATION_LOGGED.swap(true, Ordering::Relaxed) {
                warn!(
                    target: "valinor::ws::text_query",
                    "WS 'text_query' is soft-deprecated; new clients should POST to \
                     http://127.0.0.1:8770/v1/chat/completions (Hermes gateway sidecar). \
                     Existing clients keep working. This message logs once per server boot."
                );
            }
            let text = command.text.unwrap_or_default();
            let persona_name = state.current_persona.lock().await.clone();
            let persona_config = Some(state.personas.get(&persona_name)?);
            send_json(socket, &PipelineStage {
                action: "pipeline_stage",
                stage: "direct_model".to_string(),
                event: "start".to_string(),
                timestamp: now_timestamp(),
                data: json!({ "persona_name": persona_name }),
            }).await?;
            {
                send_json(
                    socket,
                    &PipelineStage {
                        action: "pipeline_stage",
                        stage: "direct_model".to_string(),
                        event: "request".to_string(),
                        timestamp: now_timestamp(),
                        data: json!({
                            "persona_name": persona_name,
                            "llama_base_url": state.config.llama_base_url,
                        }),
                    },
                )
                .await?;
                let (response_text, model_used) = match run_direct_model_turn(
                    state,
                    persona_config
                        .as_ref()
                        .ok_or_else(|| anyhow::anyhow!("persona config missing"))?,
                    &persona_name,
                    &text,
                )
                .await
                {
                    Ok(result) => result,
                    Err(err) => {
                        send_json(
                            socket,
                            &PipelineStage {
                                action: "pipeline_stage",
                                stage: "direct_model".to_string(),
                                event: "error".to_string(),
                                timestamp: now_timestamp(),
                                data: json!({
                                    "persona_name": persona_name,
                                    "kind": err.kind(),
                                    "message": err.to_string(),
                                }),
                            },
                        )
                        .await?;
                        return Err(anyhow::anyhow!(err.to_string()));
                    }
                };
                send_json(
                    socket,
                    &AiResponse {
                        action: "ai_response",
                        text: response_text,
                        persona_name,
                        has_audio: false,
                        intent: "conversation".to_string(),
                        model_used,
                        session_id: session_id.to_string(),
                        timestamp: now_timestamp(),
                    },
                )
                .await?;
            }
        }
        other => {
            send_json(
                socket,
                &ErrorMessage {
                    action: "error",
                    message: format!("unknown command: {}", other),
                },
            )
            .await?;
        }
    }
    Ok(())
}

async fn send_json<T: Serialize>(socket: &mut WebSocket, value: &T) -> Result<()> {
    socket
        .send(Message::Text(serde_json::to_string(value)?))
        .await?;
    Ok(())
}

async fn run_direct_model_turn(
    state: &AppState,
    persona_config: &Value,
    persona_name: &str,
    text: &str,
) -> std::result::Result<(String, String), LlamaChatError> {
    let deep_model = persona_config
        .get("deep_model")
        .and_then(Value::as_object)
        .ok_or_else(|| LlamaChatError::InvalidResponse("persona missing deep_model".to_string()))?;
    let system_prompt = persona_config
        .get("system_prompt")
        .and_then(Value::as_str)
        .unwrap_or("You are a helpful assistant.");
    let configured_max_tokens = deep_model
        .get("max_tokens")
        .and_then(Value::as_u64)
        .unwrap_or(512);
    let max_tokens = configured_max_tokens.min(direct_max_tokens_cap());
    let payload = json!({
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": text}
        ],
        "temperature": deep_model.get("temperature").and_then(Value::as_f64).unwrap_or(0.7),
        "top_p": deep_model.get("top_p").and_then(Value::as_f64).unwrap_or(0.9),
        "top_k": deep_model.get("top_k").and_then(Value::as_u64).unwrap_or(40),
        "repeat_penalty": deep_model.get("repeat_penalty").and_then(Value::as_f64).unwrap_or(1.0),
        "max_tokens": max_tokens,
        "chat_template_kwargs": {
            "enable_thinking": false,
        },
    });
    info!(
        "direct model call start persona={} chars={} max_tokens={} configured_max_tokens={}",
        persona_name,
        text.chars().count(),
        max_tokens,
        configured_max_tokens
    );
    let completion = state
        .llama
        .lock()
        .await
        .chat_completion(persona_config, payload)
        .await?;
    let parsed = completion.body;
    let choice = parsed
        .get("choices")
        .and_then(Value::as_array)
        .and_then(|choices| choices.first())
        .ok_or_else(|| {
            LlamaChatError::InvalidResponse("direct model response missing choices".to_string())
        })?;
    let text = choice
        .get("message")
        .and_then(|message| message.get("content"))
        .and_then(Value::as_str)
        .or_else(|| choice.get("text").and_then(Value::as_str))
        .unwrap_or("")
        .trim()
        .to_string();
    if text.is_empty() {
        return Err(LlamaChatError::InvalidResponse(
            "direct model response did not include message content".to_string(),
        ));
    }
    info!(
        "direct model call complete persona={} elapsed_s={:.3} output_chars={}",
        persona_name,
        completion.elapsed.as_secs_f64(),
        text.chars().count()
    );
    let model_used = parsed
        .get("model")
        .and_then(Value::as_str)
        .unwrap_or("llama-server")
        .to_string();
    Ok((text, model_used))
}

// ---------------------------------------------------------------------------
// ComfyUI harness endpoints — front the supervised ComfyUI for engram_comfy clients
// ---------------------------------------------------------------------------

#[derive(serde::Deserialize)]
struct ComfySubmitRequest {
    #[serde(default)]
    workflow_name: Option<String>,
    graph: Value,
    #[serde(default)]
    client_id: Option<String>,
}

async fn comfy_submit(
    State(state): State<AppState>,
    Json(payload): Json<ComfySubmitRequest>,
) -> impl IntoResponse {
    if let Err(err) = state.comfy.lock().await.ensure_started().await {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"error": {"kind": "unavailable", "message": err.to_string()}})),
        )
            .into_response();
    }
    let client_id = payload
        .client_id
        .unwrap_or_else(|| Uuid::new_v4().to_string());
    match state
        .comfy
        .lock()
        .await
        .submit(payload.graph, &client_id)
        .await
    {
        Ok(result) => (
            StatusCode::OK,
            Json(json!({
                "prompt_id": result.prompt_id,
                "number": result.number,
                "client_id": client_id,
                "workflow_name": payload.workflow_name,
            })),
        )
            .into_response(),
        Err(err) => comfy_error_response(err),
    }
}

async fn comfy_history(
    State(state): State<AppState>,
    Path(prompt_id): Path<String>,
) -> impl IntoResponse {
    match state.comfy.lock().await.fetch_history(&prompt_id).await {
        Ok(body) => (StatusCode::OK, Json(body)).into_response(),
        Err(err) => comfy_error_response(err),
    }
}

#[derive(serde::Deserialize)]
struct ComfyAssetQuery {
    #[serde(default = "default_asset_type")]
    asset_type: String,
    #[serde(default)]
    subfolder: String,
}

fn default_asset_type() -> String {
    "output".to_string()
}

async fn comfy_asset(
    State(state): State<AppState>,
    Path(filename): Path<String>,
    Query(query): Query<ComfyAssetQuery>,
) -> impl IntoResponse {
    let base = state.config.comfy_base_url();
    let mut url = format!(
        "{}/view?filename={}&type={}",
        base, filename, query.asset_type
    );
    if !query.subfolder.is_empty() {
        url.push_str(&format!("&subfolder={}", query.subfolder));
    }
    let client = reqwest::Client::new();
    match client.get(&url).send().await {
        Ok(resp) => {
            let status =
                StatusCode::from_u16(resp.status().as_u16()).unwrap_or(StatusCode::BAD_GATEWAY);
            let ct_bytes = resp
                .headers()
                .get(reqwest::header::CONTENT_TYPE)
                .map(|v| v.as_bytes().to_vec())
                .unwrap_or_else(|| b"application/octet-stream".to_vec());
            let ct_header = HeaderValue::from_bytes(&ct_bytes)
                .unwrap_or_else(|_| HeaderValue::from_static("application/octet-stream"));
            match resp.bytes().await {
                Ok(bytes) => Response::builder()
                    .status(status)
                    .header(axum::http::header::CONTENT_TYPE, ct_header)
                    .body(Body::from(bytes))
                    .unwrap_or_else(|_| {
                        (
                            StatusCode::INTERNAL_SERVER_ERROR,
                            "asset response build failed",
                        )
                            .into_response()
                    }),
                Err(err) => (
                    StatusCode::BAD_GATEWAY,
                    Json(json!({"error": {"kind": "asset_read", "message": err.to_string()}})),
                )
                    .into_response(),
            }
        }
        Err(err) => (
            StatusCode::BAD_GATEWAY,
            Json(json!({"error": {"kind": "asset_proxy", "message": err.to_string()}})),
        )
            .into_response(),
    }
}

async fn comfy_stream(
    State(state): State<AppState>,
    Path(prompt_id): Path<String>,
    upgrade: WebSocketUpgrade,
) -> impl IntoResponse {
    let comfy_ws_url = state.config.comfy_ws_url(&Uuid::new_v4().to_string());
    upgrade.on_upgrade(move |socket| forward_comfy_events(socket, comfy_ws_url, prompt_id))
}

async fn forward_comfy_events(mut socket: WebSocket, comfy_ws_url: String, expected_prompt_id: String) {
    let (mut upstream, _resp) = match tokio_tungstenite::connect_async(&comfy_ws_url).await {
        Ok(pair) => pair,
        Err(err) => {
            let _ = socket
                .send(Message::Text(
                    json!({
                        "stage": "error",
                        "kind": "upstream_unavailable",
                        "message": err.to_string(),
                    })
                    .to_string(),
                ))
                .await;
            return;
        }
    };
    use tokio_tungstenite::tungstenite::Message as TMessage;
    while let Some(Ok(msg)) = upstream.next().await {
        let TMessage::Text(raw) = msg else { continue };
        let Ok(parsed) = serde_json::from_str::<Value>(&raw) else {
            continue;
        };
        let prompt_match = parsed
            .get("data")
            .and_then(|d| d.get("prompt_id"))
            .and_then(Value::as_str)
            .map(|pid| pid == expected_prompt_id)
            .unwrap_or(true);
        if !prompt_match {
            continue;
        }
        let event = normalize_comfy_event(&parsed, &expected_prompt_id);
        if let Some(event) = event {
            let stage = event
                .get("stage")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
            if socket.send(Message::Text(event.to_string())).await.is_err() {
                break;
            }
            if matches!(stage.as_str(), "executed" | "error" | "completed") {
                break;
            }
        }
    }
    let _ = upstream.close(None).await;
}

fn normalize_comfy_event(msg: &Value, _prompt_id: &str) -> Option<Value> {
    let msg_type = msg.get("type").and_then(Value::as_str)?;
    let data = msg.get("data").cloned().unwrap_or_else(|| json!({}));
    match msg_type {
        "status" => Some(json!({
            "stage": "queued",
            "queue_remaining": data.get("status").and_then(|s| s.get("exec_info"))
                .and_then(|e| e.get("queue_remaining"))
        })),
        "execution_start" => Some(json!({"stage": "executing", "node": null})),
        "executing" => match data.get("node") {
            Some(Value::Null) | None => Some(json!({"stage": "completed"})),
            Some(node) => Some(json!({"stage": "executing", "node": node})),
        },
        "progress" => {
            let value = data.get("value").and_then(Value::as_u64).unwrap_or(0);
            let max = data.get("max").and_then(Value::as_u64).unwrap_or(1).max(1);
            let percent = (value as f64 / max as f64 * 10_000.0).round() / 100.0;
            Some(json!({
                "stage": "progress",
                "percent": percent,
                "value": value,
                "max": max,
            }))
        }
        "executed" => Some(json!({
            "stage": "executed",
            "node": data.get("node"),
            "output": data.get("output"),
        })),
        "execution_error" => Some(json!({
            "stage": "error",
            "kind": "execution_error",
            "message": data.get("exception_message").and_then(Value::as_str).unwrap_or("ComfyUI error"),
            "node": data.get("node_id"),
        })),
        _ => None,
    }
}

fn comfy_error_response(err: ComfyError) -> axum::response::Response {
    let status = match &err {
        ComfyError::Timeout { .. } => StatusCode::GATEWAY_TIMEOUT,
        ComfyError::Request(_) | ComfyError::InvalidResponse(_) => StatusCode::BAD_GATEWAY,
        ComfyError::Http { status, .. } => {
            StatusCode::from_u16(*status).unwrap_or(StatusCode::BAD_GATEWAY)
        }
        ComfyError::InvalidWorkflow(_) => StatusCode::BAD_REQUEST,
        ComfyError::OutOfMemory(_) => StatusCode::SERVICE_UNAVAILABLE,
        ComfyError::RestartFailed { .. } => StatusCode::SERVICE_UNAVAILABLE,
    };
    (
        status,
        Json(json!({
            "error": {
                "kind": err.kind(),
                "message": err.to_string(),
            }
        })),
    )
        .into_response()
}

fn direct_max_tokens_cap() -> u64 {
    std::env::var("HEARTH_RUST_DIRECT_MAX_TOKENS")
        .ok()
        .and_then(|value| value.trim().parse::<u64>().ok())
        .filter(|value| *value > 0)
        .unwrap_or(256)
}

