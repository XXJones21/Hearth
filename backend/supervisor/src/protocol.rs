use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Deserialize)]
pub struct ClientCommand {
    pub action: String,
    #[serde(default)]
    pub platform: Option<String>,
    #[serde(default)]
    pub capabilities: Value,
    #[serde(default)]
    pub persona_name: Option<String>,
    #[serde(default)]
    pub text: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ServerCapabilities {
    pub audio_generation: bool,
    pub voice_cloning: bool,
    pub spatial_support: bool,
}

#[derive(Debug, Serialize)]
pub struct ClientInfoAck {
    pub action: &'static str,
    pub status: &'static str,
    pub server_capabilities: ServerCapabilities,
}

#[derive(Debug, Serialize)]
pub struct PersonaList {
    pub action: &'static str,
    pub personas: Vec<crate::persona::PersonaMetadata>,
    pub current_persona: String,
}

#[derive(Debug, Serialize)]
pub struct PersonaConfig {
    pub action: &'static str,
    pub persona_name: String,
    pub config: Value,
}

#[derive(Debug, Serialize)]
pub struct PersonaSwitched {
    pub action: &'static str,
    pub persona_name: String,
    pub status: &'static str,
}

#[derive(Debug, Serialize)]
pub struct ErrorMessage {
    pub action: &'static str,
    pub message: String,
}

#[derive(Debug, Serialize)]
pub struct PipelineStage {
    pub action: &'static str,
    pub stage: String,
    pub event: String,
    pub timestamp: String,
    #[serde(flatten)]
    pub data: Value,
}

#[derive(Debug, Serialize)]
pub struct AiResponse {
    pub action: &'static str,
    pub text: String,
    pub persona_name: String,
    pub has_audio: bool,
    pub intent: String,
    pub model_used: String,
    pub session_id: String,
    pub timestamp: String,
}

#[derive(Debug, Serialize)]
pub struct PingResponse {
    pub action: &'static str,
    pub status: &'static str,
    pub uptime_s: u64,
    pub current_persona: String,
    pub llama_ready: bool,
    pub active_model: Option<String>,
}

pub fn now_timestamp() -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    format!("{}.{:03}Z", now.as_secs(), now.subsec_millis())
}
