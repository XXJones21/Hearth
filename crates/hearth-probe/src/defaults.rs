//! Product constants with exactly one home.
//!
//! Anything here is a fact of the product, not of a machine: the port block,
//! the first-run persona, the layout under the install root. The installer
//! renders these into `<root>/config/hearth.env`; everything that runs
//! afterward reads that file and only that file. No consumer may carry its
//! own copy of a value in this module as a "default": that is how the same
//! number ends up living in four files and being wrong in one of them.
//!
//! The client's TypeScript keeps its own dial-out default (`config.ts`),
//! because the webview cannot import Rust; it must match PORT_GATEWAY, and a
//! mismatch is caught the first time a fresh install cannot connect to the
//! house it just started.

/// Hearth's own port block. Deliberately not the internal Valinor stack's
/// 8700/8080/8765/8766/8702, so a build reaching a development machine finds
/// nothing rather than finding the live house.
pub const PORT_GATEWAY: u16 = 18700;
pub const PORT_LLAMA: u16 = 18080;
pub const PORT_SUPERVISOR_WS: u16 = 18765;
pub const PORT_SUPERVISOR_ASSETS: u16 = 18766;
pub const PORT_TTS: u16 = 18702;
/// The voice ENGINE, one hop behind the TTS service on PORT_TTS. The service
/// keeps the websocket contract the gateway speaks; the engine holds the
/// weights and answers OpenAI's /v1/audio/speech behind it.
pub const PORT_TTS_ENGINE: u16 = 18703;

/// The persona every install starts with. He ships in the client bundle so
/// first run can draw him with nothing listening, and the backend copy is
/// provisioned from the same file.
pub const FIRST_PERSONA: &str = "Sulivan";

/// Layout under the install root, relative paths the renderer writes as
/// absolute. One folder; deleting it is the uninstall. Interpreter and
/// binary locations differ per platform (venvs put python under Scripts on
/// Windows and bin elsewhere; nothing ends in .exe on macOS), so those are
/// functions of the OS this build runs on.
pub const REL_MODELS: &str = "models";
pub const REL_BACKEND: &str = "runtime/backend";
/// The second-brain memory client (engram-mcp), vendored into the backend
/// bundle by pack_backend.sh. First run establishes a brain for every new
/// user, so the client that reads it deeply is product, not dev tooling:
/// without this path the harness's EngramService stays dark and recall
/// degrades to the legacy seams.
pub const REL_ENGRAM_MCP: &str = "runtime/backend/vendor/engram-mcp";
pub const REL_HOME: &str = "home";
pub const REL_ENGRAM: &str = "home/engram";
pub const REL_HF_CACHE: &str = "home/hf-cache";
pub const REL_LOGS: &str = "logs";
pub const REL_CONFIG: &str = "config/hearth.env";

pub fn rel_python() -> &'static str {
    if cfg!(windows) { "runtime/python/python.exe" } else { "runtime/python/bin/python3" }
}

pub fn rel_supervisor() -> &'static str {
    if cfg!(windows) { "runtime/hearth-supervisor.exe" } else { "runtime/hearth-supervisor" }
}

pub fn rel_llama_server() -> &'static str {
    if cfg!(windows) {
        "runtime/llama-server/llama-server.exe"
    } else {
        "runtime/llama-server/llama-server"
    }
}

pub fn rel_voice_python() -> &'static str {
    if cfg!(windows) { "envs/voice/Scripts/python.exe" } else { "envs/voice/bin/python" }
}

/// The voice engine binary, unpacked from the bundle beside the supervisor.
pub fn rel_tts_server() -> &'static str {
    if cfg!(windows) { "runtime/tts-server.exe" } else { "runtime/tts-server" }
}

/// The voice DESIGN tool, from the same build and unpacked beside the engine.
///
/// A separate binary because tts-server cannot design: its /v1/audio/speech
/// validates `voice` against the names loaded at ITS startup, so instruct
/// attributes have no way through. Design runs once per persona, at creation.
pub fn rel_omnivoice_tts() -> &'static str {
    if cfg!(windows) { "runtime/omnivoice-tts.exe" } else { "runtime/omnivoice-tts" }
}

/// Voice weights live with the other weights, not in the Hugging Face cache:
/// they are named files the installer verifies, not a repository snapshot.
pub const REL_VOICE_MODELS: &str = "models/voice";
