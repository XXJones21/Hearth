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

/// The persona every install starts with. He ships in the client bundle so
/// first run can draw him with nothing listening, and the backend copy is
/// provisioned from the same file.
pub const FIRST_PERSONA: &str = "Sulivan";

/// Layout under the install root, relative paths the renderer writes as
/// absolute. One folder; deleting it is the uninstall.
pub const REL_MODELS: &str = "models";
pub const REL_BACKEND: &str = "runtime/backend";
pub const REL_PYTHON: &str = "runtime/python/python.exe";
pub const REL_SUPERVISOR: &str = "runtime/hearth-supervisor.exe";
pub const REL_LLAMA_SERVER: &str = "runtime/llama-server/llama-server.exe";
pub const REL_HOME: &str = "home";
pub const REL_ENGRAM: &str = "home/engram";
pub const REL_HF_CACHE: &str = "home/hf-cache";
pub const REL_VOICE_PYTHON: &str = "envs/voice/Scripts/python.exe";
pub const REL_LOGS: &str = "logs";
pub const REL_CONFIG: &str = "config/hearth.env";
