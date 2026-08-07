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
use tauri::Emitter;

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
    #[cfg(windows)]
    _job: Arc<win32job::Job>,
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
    let file = parse_env_file(&config_path);
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
    harness_env.insert(
        "PYTHONPATH".into(),
        format!("{};{}", slash(&backend), slash(&backend.join("harness"))),
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
            program: python,
            args: vec!["app.py".into()],
            cwd: backend.join("harness"),
            env: harness_env.clone(),
            health_port: gateway_port.parse().ok(),
        },
    ];

    // The voice service is optional by design: the house runs text-only
    // without it, and an install that skipped or failed the voice row still
    // gets a working Hearth. Present and provisioned means supervised, with
    // one honest exception: on a machine whose plan said the mind and the
    // voice cannot both stay resident (HEARTH_COEXIST=0, the 8 GB Air), the
    // voice does not boot resident. The take-turns orchestration the small-
    // machine screen promises is designed and not yet built; text-first is
    // the truthful interim, not a silent overcommit that swaps the machine
    // to a crawl.
    let coexist = file.get("HEARTH_COEXIST").map(|v| v != "0").unwrap_or(true);
    if !coexist {
        // fall through with no voice spec
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

fn spawn(spec: &Spec, logs_dir: &Path) -> std::io::Result<Child> {
    let log = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(logs_dir.join(format!("{}.log", spec.name)))?;
    let err = log.try_clone()?;
    let mut cmd = Command::new(&spec.program);
    cmd.args(&spec.args)
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
        #[cfg(windows)]
        _job: job.clone(),
    };
    *state.lock().unwrap() = Some(house);
    Ok(())
}

pub fn stop(state: &HouseState) {
    let mut guard = state.lock().unwrap();
    if let Some(house) = guard.take() {
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

#[tauri::command]
pub fn house_start(
    app: tauri::AppHandle,
    state: tauri::State<'_, HouseState>,
    root: String,
) -> Result<(), String> {
    start(app, &state, PathBuf::from(root))
}

#[tauri::command]
pub fn house_stop(state: tauri::State<'_, HouseState>) {
    stop(&state);
}

#[tauri::command]
pub fn house_status(state: tauri::State<'_, HouseState>) -> HouseStatus {
    status(&state)
}
