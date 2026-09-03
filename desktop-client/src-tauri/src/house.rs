//! The house: the backend process tree, supervised by the client.
//!
//! This module is what replaced systemd when the backend went native. The
//! three units provided seven behaviors (ordering, restart-on-exit, tree
//! reaping, no start timeout, an environment file, per-process interpreter,
//! start at login) and each one lives here now, in the process the user
//! actually runs.
//!
//! Restart-on-exit is not just crash recovery: the harness applies persona
//! and app settings by calling os._exit(0) and trusting its supervisor to
//! bring it back. Without the restart loop, saving a persona edit shuts the
//! product down.

use serde::Serialize;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::{Emitter, Manager};

#[cfg(windows)]
use std::os::windows::process::CommandExt;
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// One supervised process.
struct Spec {
    name: &'static str,
    program: PathBuf,
    args: Vec<String>,
    cwd: PathBuf,
    env: HashMap<String, String>,
    /// TCP port that answers when this process is ready. The gate between
    /// ordered stages; None means "spawned is ready".
    health_port: Option<u16>,
}

#[derive(Clone, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ProcStatus {
    pub name: String,
    /// "starting" | "running" | "restarting" | "stopped" | "failed"
    pub state: String,
    pub pid: Option<u32>,
    pub restarts: u32,
    pub detail: String,
}

#[derive(Clone, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct HouseStatus {
    pub running: bool,
    pub root: String,
    pub processes: Vec<ProcStatus>,
}

struct Managed {
    child: Child,
    name: &'static str,
}

pub struct House {
    stopping: Arc<AtomicBool>,
    children: Arc<Mutex<Vec<Managed>>>,
    status: Arc<Mutex<HouseStatus>>,
    /// The gateway's port, kept so stop() can ask it to file the live
    /// conversation before the tree is killed.
    gateway_port: Option<u16>,
    #[cfg(windows)]
    _job: Arc<win32job::Job>,
}

/// Ask the house to write down whatever conversation is open, and wait for it.
///
/// Quit stops the backend within milliseconds of the socket closing, so the
/// server's own teardown never finished: it began summarising and was killed
/// mid-call. This is the handshake that fixes it. The endpoint makes no model
/// call, so the normal answer arrives in well under a second; the timeout is
/// only here so a wedged house cannot hold the app open.
///
/// Hand-rolled rather than pulling in an HTTP client: it is one loopback POST
/// with no body, and a dependency for that would be a poor trade.
fn flush_sessions(port: u16) {
    use std::io::{Read, Write};
    use std::net::TcpStream;

    let addr = format!("127.0.0.1:{port}");
    let deadline = Duration::from_secs(5);
    let Ok(mut stream) = TcpStream::connect(&addr) else {
        return; // nothing listening; nothing to flush
    };
    let _ = stream.set_read_timeout(Some(deadline));
    let _ = stream.set_write_timeout(Some(deadline));
    let req = format!(
        "POST /sessions/flush HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n\
         Content-Length: 0\r\nConnection: close\r\n\r\n"
    );
    if stream.write_all(req.as_bytes()).is_err() {
        return;
    }
    // Reading to the end is the point: returning early would put us back in
    // the race this exists to end.
    let mut buf = Vec::new();
    let _ = stream.read_to_end(&mut buf);
    let head = String::from_utf8_lossy(&buf);
    let ok = head.starts_with("HTTP/1.1 200");
    log::info!(
        "house flush: {}",
        if ok { "sessions filed" } else { "no answer" }
    );
}

pub type HouseState = Mutex<Option<House>>;

/// KEY=VALUE lines, comments and blanks ignored. The EnvironmentFile=
/// equivalent; systemd read this file and now we do.
fn parse_env_file(path: &Path) -> HashMap<String, String> {
    let mut map = HashMap::new();
    let Ok(text) = std::fs::read_to_string(path) else {
        return map;
    };
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some((key, value)) = line.split_once('=') {
            map.insert(key.trim().to_string(), value.trim().to_string());
        }
    }
    map
}

fn slash(p: &Path) -> String {
    p.to_string_lossy().replace('\\', "/")
}

/// The specs for this install root, read from the installer's rendered
/// hearth.env and nowhere else. This layer carries NO configuration of its
/// own: the installer decided the values (see config_gen.rs and
/// hearth_probe::defaults), and a missing file or key is a provisioning
/// failure to report, not a gap to paper over with a built-in copy.
fn build_specs(root: &Path) -> Result<(Vec<Spec>, PathBuf), String> {
    let config_path = root.join("config").join("hearth.env");
    if !config_path.is_file() {
        return Err(format!(
            "no configuration at {}. Setup has not provisioned this install; \
             re-run setup, or repair with the config renderer.",
            config_path.display()
        ));
    }
    let mut file = parse_env_file(&config_path);
    // Optional overlay: keys win over hearth.env so a supervisor can point
    // this house at another household without rewriting the product file.
    if let Ok(overlay) = std::env::var("HEARTH_ENV_OVERLAY") {
        let overlay_path = PathBuf::from(&overlay);
        if overlay_path.is_file() {
            for (k, v) in parse_env_file(&overlay_path) {
                file.insert(k, v);
            }
        }
    }
    let require = |key: &str| -> Result<String, String> {
        file.get(key).cloned().ok_or_else(|| {
            format!("{} is missing {}; re-render the configuration", config_path.display(), key)
        })
    };

    let backend = PathBuf::from(require("HEARTH_BACKEND_DIR")?);
    if !backend.join("harness").join("app.py").is_file() {
        return Err(format!(
            "no backend at {} (harness/app.py missing); provisioning has not \
             placed the runtime, or hearth.env points at the wrong place",
            backend.display()
        ));
    }
    let python = PathBuf::from(require("HEARTH_PYTHON")?);
    if !python.is_file() {
        return Err(format!("no python at {}", python.display()));
    }
    let supervisor_bin = PathBuf::from(require("HEARTH_SUPERVISOR_BIN")?);
    if !supervisor_bin.is_file() {
        return Err(format!("no supervisor at {}", supervisor_bin.display()));
    }
    // The weights the plan chose, checked here rather than discovered by
    // llama-server four screens later. This failure used to surface as a
    // refused WebSocket during the first conversation, with setup already
    // reporting success and the person waiting on a reply that could never
    // come. An install that cannot serve a model is not an install.
    if let Some(model) = file.get("HEARTH_DEEP_MODEL_FILE") {
        let model = PathBuf::from(model);
        if !model.is_file() {
            return Err(format!(
                "the planned model is not on disk: {}. The download did not finish, or the \
                 models directory was moved after install; re-run setup to fetch it.",
                model.display()
            ));
        }
    }
    if let Some(llama) = file.get("HEARTH_LLAMA_SERVER_BIN") {
        let llama = PathBuf::from(llama);
        if !llama.is_file() {
            return Err(format!(
                "no llama-server at {}; provisioning did not unpack it",
                llama.display()
            ));
        }
    }
    let gateway_port = require("HEARTH_PORT")?;
    let ws_port = require("HEARTH_RUST_WS_PORT")?;

    // The two directories the file names that must exist before anything
    // runs. Engram seeds empty, never clones; idempotent either way.
    if let Some(engram) = file.get("HEARTH_ENGRAM") {
        for sub in ["Projects", "Areas", "Thoughts", "Resources"] {
            let _ = std::fs::create_dir_all(Path::new(engram).join(sub));
        }
    }
    let logs_dir = PathBuf::from(require("HEARTH_LOG_DIR")?);
    let _ = std::fs::create_dir_all(&logs_dir);

    // Children see the file verbatim, plus the two mechanical values that
    // are derived rather than configured.
    let mut env: HashMap<String, String> = file.clone();
    env.insert("HEARTH_ROOT".into(), slash(&backend));
    let mut harness_env = env.clone();
    // PYTHONPATH is a path LIST, and its separator is the platform's, not the
    // path separator. Semicolon was hardcoded when Windows was the only
    // target; on macOS it makes both entries one nonexistent directory, which
    // Python discards in silence. The harness only kept importing because its
    // working directory covered for it.
    let listsep = if cfg!(windows) { ";" } else { ":" };
    harness_env.insert(
        "PYTHONPATH".into(),
        format!("{}{}{}", slash(&backend), listsep, slash(&backend.join("harness"))),
    );
    // Line-buffered logs; a crash with an empty log file is a mystery.
    harness_env.insert("PYTHONUNBUFFERED".into(), "1".into());
    // The vendored python must never import the machine owner's Roaming
    // site-packages; a stale huggingface_hub from there broke an install.
    harness_env.insert("PYTHONNOUSERSITE".into(), "1".into());

    let mut specs = vec![
        Spec {
            name: "supervisor",
            program: supervisor_bin,
            args: vec![],
            cwd: backend.clone(),
            env,
            health_port: ws_port.parse().ok(),
        },
        Spec {
            name: "harness",
            program: python.clone(),
            args: vec!["app.py".into()],
            cwd: backend.join("harness"),
            env: harness_env.clone(),
            health_port: gateway_port.parse().ok(),
        },
    ];

    // The voice service is optional by design: the house runs text-only
    // without it, and an install that skipped or failed the voice row still
    // gets a working Hearth. Present and provisioned means supervised.
    //
    // HEARTH_COEXIST no longer gates this. It used to: a plan that said the
    // mind and the voice could not both stay resident kept the voice out of
    // memory entirely, which on an 8 GB Air meant silence. That was the torch
    // engine's 2.2 GiB talking. The C++ engine holds about 900 MB and the same
    // machine now plans coexist:true, so the flag has nothing left to decide
    // here; the planner already refused any model that would not leave room.
    //
    // The C++ engine: a shipped binary holding the weights, with the Python
    // service in front of it keeping the websocket contract the gateway
    // speaks. Two processes where the torch build was one, and about a third
    // of the memory, which is what lets an 8 GB machine keep both the mind and
    // the voice resident. Each persona's reference clip is loaded by name at
    // the engine's startup, because encoding is the expensive half of cloning
    // and doing it once is the whole point of a resident engine.
    let engine_bin = file.get("HEARTH_TTS_ENGINE_BIN").map(PathBuf::from);
    if let Some(engine) = engine_bin.filter(|p| p.is_file()) {
        let models = PathBuf::from(file.get("HEARTH_TTS_VOICE_MODELS").cloned().unwrap_or_default());
        let base = models.join("omnivoice-base-Q8_0.gguf");
        let codec = models.join("omnivoice-tokenizer-Q8_0.gguf");
        if !base.is_file() || !codec.is_file() {
            return Err(format!(
                "the voice engine has no weights: expected {} and {}. Re-run setup to fetch them.",
                base.display(),
                codec.display()
            ));
        }
        let mut args: Vec<String> = vec![
            "--model".into(),
            slash(&base),
            "--codec".into(),
            slash(&codec),
            "--host".into(),
            "127.0.0.1".into(),
            "--port".into(),
            file.get("HEARTH_TTS_ENGINE_PORT").cloned().unwrap_or_else(|| "18703".into()),
            "--lang".into(),
            "English".into(),
        ];
        if let Some(steps) = file.get("HEARTH_TTS_STEPS") {
            args.push("--steps".into());
            args.push(steps.clone());
        }
        // Relative to cwd=backend so a junction target that canonicalizes
        // onto D:\Tools\... does not put a drive-letter colon in --voice.
        for v in persona_voice_args(&backend) {
            args.push("--voice".into());
            args.push(v);
        }
        specs.push(Spec {
            name: "voice-engine",
            program: engine,
            args,
            cwd: backend.clone(),
            env: harness_env.clone(),
            health_port: file.get("HEARTH_TTS_ENGINE_PORT").and_then(|p| p.parse().ok()),
        });
        // The service in front of it runs on the main interpreter: with the
        // engine holding the weights, this side needs only fastapi, uvicorn
        // and websockets, which the harness already has. No voice venv.
        specs.push(Spec {
            name: "voice",
            program: python.clone(),
            args: vec!["tts_app.py".into()],
            cwd: backend.join("harness"),
            env: harness_env.clone(),
            health_port: file.get("HEARTH_TTS_PORT").and_then(|p| p.parse().ok()),
        });
    } else if let Some(voice_py) = file.get("HEARTH_VOICE_PYTHON") {
        let voice_py = PathBuf::from(voice_py);
        if voice_py.is_file() {
            specs.push(Spec {
                name: "voice",
                program: voice_py,
                args: vec!["tts_app.py".into()],
                cwd: backend.join("harness"),
                env: harness_env,
                health_port: file
                    .get("HEARTH_TTS_PORT")
                    .and_then(|p| p.parse().ok()),
            });
        }
    }

    Ok((specs, logs_dir))
}

/// Every persona voice, as ready --voice values (name:clip:transcript,
/// cwd-relative and drive-letter-free). The persona's DIRECTORY names the
/// primary voice, lowercased, which is the same rule valar/voice/tts_cpp.py
/// applies when it turns a persona into a voice name -- so the two agree
/// without a table between them that could fall out of step.
///
/// Any FURTHER wav+txt pair sitting directly in the voice folder registers
/// as "<persona>-<stem>", lowercased. That is what per-sentence voice
/// oscillation (the manifest's voice.oscillate list, read by tts_cpp)
/// selects between; a clip without its transcript sidecar is skipped, same
/// rule as the primary.
///
/// A persona with no clip is simply absent: the engine refuses a voice it was
/// never given, which is what makes a missing reference a loud failure at the
/// first request rather than a persona quietly speaking in a stranger's voice.
fn persona_voice_args(backend: &Path) -> Vec<String> {
    let mut out = Vec::new();
    let dir = backend.join("personas");
    let Ok(entries) = std::fs::read_dir(&dir) else {
        return out;
    };
    let mut names: Vec<_> = entries.flatten().map(|e| e.path()).collect();
    // Deterministic order, so the engine's --voice list and the logs it prints
    // do not shuffle between boots.
    names.sort();
    for p in names {
        if !p.is_dir() {
            continue;
        }
        let Some(persona) = p.file_name().and_then(|n| n.to_str()) else {
            continue;
        };
        let lower = persona.to_lowercase();
        let voice_dir = p.join("voice");
        let primary = format!("{lower}_voice_reference");
        if voice_dir.join(format!("{primary}.wav")).is_file()
            && voice_dir.join(format!("{primary}.txt")).is_file()
        {
            out.push(format!(
                "{lower}:personas/{persona}/voice/{primary}.wav:personas/{persona}/voice/{primary}.txt"
            ));
        }
        let Ok(clips) = std::fs::read_dir(&voice_dir) else {
            continue;
        };
        let mut extra: Vec<_> = clips.flatten().map(|e| e.path()).collect();
        extra.sort();
        for clip in extra {
            if clip.extension().and_then(|e| e.to_str()) != Some("wav") {
                continue;
            }
            let Some(stem) = clip.file_stem().and_then(|s| s.to_str()) else {
                continue;
            };
            let stem_lower = stem.to_lowercase();
            if stem_lower == primary {
                continue;
            }
            if !clip.with_extension("txt").is_file() {
                continue;
            }
            out.push(format!(
                "{lower}-{stem_lower}:personas/{persona}/voice/{stem}.wav:personas/{persona}/voice/{stem}.txt"
            ));
        }
    }
    out
}

/// The voice engine's args, refreshed at every (re)spawn: the startup list
/// only knew the personas that existed when the house rose, and the whole
/// point of reloading the engine (house_reload_voice) is a persona made five
/// minutes in. Everything except the --voice pairs passes through untouched.
fn refresh_voice_args(spec: &Spec) -> Vec<String> {
    let mut kept = Vec::new();
    let mut it = spec.args.iter();
    while let Some(a) = it.next() {
        if a == "--voice" {
            let _ = it.next();
        } else {
            kept.push(a.clone());
        }
    }
    for v in persona_voice_args(&spec.cwd) {
        kept.push("--voice".into());
        kept.push(v);
    }
    kept
}

fn spawn(spec: &Spec, logs_dir: &Path) -> std::io::Result<Child> {
    let log = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(logs_dir.join(format!("{}.log", spec.name)))?;
    let err = log.try_clone()?;
    let args = if spec.name == "voice-engine" {
        refresh_voice_args(spec)
    } else {
        spec.args.clone()
    };
    let mut cmd = Command::new(&spec.program);
    cmd.args(&args)
        .current_dir(&spec.cwd)
        .envs(&spec.env)
        .stdout(Stdio::from(log))
        .stderr(Stdio::from(err))
        .stdin(Stdio::null());
    #[cfg(windows)]
    cmd.creation_flags(CREATE_NO_WINDOW);
    // Each supervised process leads its own process group, so stopping it
    // can take its children too (llama-server under the supervisor). The
    // unix counterpart of the Windows Job Object, weaker but sufficient.
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        cmd.process_group(0);
    }
    cmd.spawn()
}

/// Kill a supervised process and, on unix, its whole process group.
fn kill_managed(managed: &mut Managed) {
    #[cfg(unix)]
    unsafe {
        let pgid = managed.child.id() as i32;
        libc::killpg(pgid, libc::SIGTERM);
        std::thread::sleep(Duration::from_millis(300));
        libc::killpg(pgid, libc::SIGKILL);
    }
    let _ = managed.child.kill();
}

fn port_answers(port: u16) -> bool {
    std::net::TcpStream::connect_timeout(
        &std::net::SocketAddr::from(([127, 0, 0, 1], port)),
        Duration::from_secs(2),
    )
    .is_ok()
}

fn set_status(
    app: &tauri::AppHandle,
    status: &Arc<Mutex<HouseStatus>>,
    name: &str,
    state: &str,
    pid: Option<u32>,
    restarts: u32,
    detail: &str,
) {
    {
        let mut s = status.lock().unwrap();
        if let Some(p) = s.processes.iter_mut().find(|p| p.name == name) {
            p.state = state.to_string();
            p.pid = pid;
            p.restarts = restarts;
            p.detail = detail.to_string();
        }
        s.running = s.processes.iter().any(|p| p.state == "running");
        let _ = app.emit("house-status", s.clone());
    }
}

/// Start the tree. Ordered: each stage's health gate opens the next, with a
/// generous ceiling because a cold model load is minutes, not seconds
/// (systemd ran these with TimeoutStartSec=0).
pub fn start(app: tauri::AppHandle, state: &HouseState, root: PathBuf) -> Result<(), String> {
    stop(state);

    let (specs, logs_dir) = build_specs(&root)?;
    // The gateway is the one child with a conversation in it, so its port is
    // the one stop() has to knock on before killing anything.
    let gateway_port = specs
        .iter()
        .find(|s| s.name == "harness")
        .and_then(|s| s.health_port);

    // One house per machine, and the port is the guard rather than a lock
    // file: a lock file outlives the process that wrote it and then lies,
    // while a listening socket IS the house. stop() ran above, so anything
    // still answering belongs to SOMEONE ELSE, and starting over it puts two
    // llama-servers on one GPU and two harnesses on one Engram.
    //
    // Live on 2026-09-03: a release build installed to debug a customer issue
    // started its own house first, and the next client adopted it. The
    // household came up with the wrong personas and the operator's own were
    // nowhere. Valinor spec 2026-09-03-house-as-a-service-design.md, section 3.
    if let Some(port) = gateway_port {
        if port_answers(port) {
            return Err(format!(
                "a house already answers on {port}; refusing to start a second"
            ));
        }
    }

    let stopping = Arc::new(AtomicBool::new(false));
    let children: Arc<Mutex<Vec<Managed>>> = Arc::new(Mutex::new(Vec::new()));
    let status = Arc::new(Mutex::new(HouseStatus {
        running: false,
        root: root.to_string_lossy().to_string(),
        processes: specs
            .iter()
            .map(|s| ProcStatus {
                name: s.name.to_string(),
                state: "starting".into(),
                ..Default::default()
            })
            .collect(),
    }));

    // One Job Object for the whole tree. Each SPAWNED child is assigned to
    // it (never this process: the job is kill-on-close, and the client must
    // survive a house stop), and children of a job member join the job, so
    // llama-server is covered too. If the client dies without running a
    // line of cleanup, its handles close, the job closes, and the OS reaps
    // the tree. This is the systemd cgroup guarantee, or as close as
    // Windows offers.
    #[cfg(windows)]
    let job = {
        let job = win32job::Job::create().map_err(|e| e.to_string())?;
        let mut info = job.query_extended_limit_info().map_err(|e| e.to_string())?;
        info.limit_kill_on_job_close();
        job.set_extended_limit_info(&info).map_err(|e| e.to_string())?;
        Arc::new(job)
    };

    for spec in specs {
        let stopping = stopping.clone();
        let children = children.clone();
        let status = status.clone();
        let logs_dir = logs_dir.clone();
        let app = app.clone();
        #[cfg(windows)]
        let job = job.clone();

        // The gate: wait for this stage before spawning the monitor for the
        // next... except ordering here is soft, as it was under systemd
        // (After= with services that tolerate a briefly absent peer). Each
        // process gets its own monitor thread; the health wait only affects
        // what we report.
        std::thread::spawn(move || {
            let mut restarts: u32 = 0;
            loop {
                if stopping.load(Ordering::SeqCst) {
                    break;
                }
                let child = match spawn(&spec, &logs_dir) {
                    Ok(c) => c,
                    Err(e) => {
                        set_status(&app, &status, spec.name, "failed", None, restarts, &e.to_string());
                        break;
                    }
                };
                let pid = child.id();
                #[cfg(windows)]
                {
                    use std::os::windows::io::AsRawHandle;
                    let _ = job.assign_process(child.as_raw_handle() as isize);
                }
                children.lock().unwrap().push(Managed { child, name: spec.name });
                set_status(&app, &status, spec.name, "starting", Some(pid), restarts, "");

                if let Some(port) = spec.health_port {
                    let deadline = Instant::now() + Duration::from_secs(300);
                    while Instant::now() < deadline && !stopping.load(Ordering::SeqCst) {
                        if port_answers(port) {
                            set_status(&app, &status, spec.name, "running", Some(pid), restarts, "");
                            break;
                        }
                        std::thread::sleep(Duration::from_secs(1));
                    }
                } else {
                    set_status(&app, &status, spec.name, "running", Some(pid), restarts, "");
                }

                // Wait for exit by polling the managed list; the child
                // handle lives there so stop() can kill it.
                let exit_code: Option<i32> = loop {
                    if stopping.load(Ordering::SeqCst) {
                        break None;
                    }
                    let mut list = children.lock().unwrap();
                    let Some(entry) = list.iter_mut().find(|m| m.name == spec.name) else {
                        break None;
                    };
                    match entry.child.try_wait() {
                        Ok(Some(code)) => {
                            let idx = list.iter().position(|m| m.name == spec.name).unwrap();
                            list.remove(idx);
                            break Some(code.code().unwrap_or(-1));
                        }
                        Ok(None) => {}
                        Err(_) => break None,
                    }
                    drop(list);
                    std::thread::sleep(Duration::from_millis(500));
                };

                if stopping.load(Ordering::SeqCst) {
                    break;
                }
                // Unexpected exit. This is the Restart=always seam the
                // settings-apply path (os._exit(0)) depends on.
                restarts += 1;
                let backoff = Duration::from_secs(5).min(Duration::from_secs(5 * restarts as u64));
                set_status(
                    &app,
                    &status,
                    spec.name,
                    "restarting",
                    None,
                    restarts,
                    &format!("exited with {:?}; back in {}s", exit_code, backoff.as_secs()),
                );
                std::thread::sleep(backoff);
            }
            if stopping.load(Ordering::SeqCst) {
                set_status(&app, &status, spec.name, "stopped", None, restarts, "");
            }
        });
    }

    let house = House {
        stopping,
        children,
        status,
        gateway_port,
        #[cfg(windows)]
        _job: job.clone(),
    };
    *state.lock().unwrap() = Some(house);
    Ok(())
}

pub fn stop(state: &HouseState) {
    let mut guard = state.lock().unwrap();
    if let Some(house) = guard.take() {
        // Ask before killing. The conversation lives in the gateway's memory
        // and is written only when a session ends, so a kill with no warning
        // is how a day of talking disappears.
        if let Some(port) = house.gateway_port {
            flush_sessions(port);
        }
        house.stopping.store(true, Ordering::SeqCst);
        let mut children = house.children.lock().unwrap();
        for managed in children.iter_mut() {
            kill_managed(managed);
        }
        children.clear();
        // The Job Object handle drops here; KILL_ON_JOB_CLOSE reaps anything
        // the explicit kills missed, llama-server included.
    }
}

pub fn status(state: &HouseState) -> HouseStatus {
    state
        .lock()
        .unwrap()
        .as_ref()
        .map(|h| h.status.lock().unwrap().clone())
        .unwrap_or_default()
}

/// Bring the house up, or bounce it: `start` stops whatever this instance is
/// already supervising before it spawns anything, so a second call IS the
/// restart and the client needs no separate command for it.
///
/// Async, and the work goes to a blocking worker. As a sync command this ran
/// on the UI thread through a process spawn and a health gate that waits on
/// llama-server loading a model, which is tens of seconds with the window
/// unable to paint: Windows marks it Not Responding and the operator is told
/// their new app has hung on first run. The boot overlay can only animate if
/// this thread is free.
#[tauri::command]
pub async fn house_start(app: tauri::AppHandle, root: String) -> Result<(), String> {
    let worker = app.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let state = worker.state::<HouseState>();
        start(worker.clone(), &state, PathBuf::from(root))
    })
    .await
    .map_err(|e| format!("house start worker failed: {e}"))?
}

#[tauri::command]
pub fn house_stop(state: tauri::State<'_, HouseState>) {
    stop(&state);
}

#[tauri::command]
pub fn house_status(state: tauri::State<'_, HouseState>) -> HouseStatus {
    status(&state)
}

/// Bounce the voice engine so it wakes with every persona that exists NOW.
/// The engine loads its named voices at startup, so a persona made after the
/// house rose has a designed clip on disk the running engine has never heard
/// of. Killing the child is the whole implementation: the monitor thread
/// respawns it, and spawn() rescans the personas for the --voice list. The
/// caller (the interview's handover) gates the new persona's first words on
/// /voice/ready coming back.
#[tauri::command]
pub fn house_reload_voice(state: tauri::State<'_, HouseState>) -> bool {
    let guard = state.lock().unwrap();
    let Some(house) = guard.as_ref() else {
        return false;
    };
    let mut list = house.children.lock().unwrap();
    if let Some(entry) = list.iter_mut().find(|m| m.name == "voice-engine") {
        let _ = entry.child.kill();
        return true;
    }
    false
}
