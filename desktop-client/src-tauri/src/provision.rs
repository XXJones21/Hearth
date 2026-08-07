//! Provisioning: everything the installing screen places besides the models.
//!
//! Parallel where the work allows, because setup time is first-impression
//! time. Three chains run alongside the model download the moment provision
//! starts: the bundled backend unpacks, the inference engine fetches, and
//! the Python runtime lands. When Python is in place the tree forks again:
//! the harness requirements and then the voice MODEL fetch on one side, the
//! voice engine's own environment (venv, torch, the engine) on the other.
//! The model fetch rides the runtime python's huggingface_hub precisely so
//! it does not queue behind torch; two pips cannot share one env.
//!
//! Every artifact's source, size and hash live in the dictionary; nothing
//! here names a URL. Idempotent by construction: fetches skip files already
//! at exact size, unpacks clear their target first. Retry is rerun.

use hearth_probe::{dict::RuntimeArtifact, Dictionary};
use std::path::{Path, PathBuf};
use tauri::ipc::Channel;
use tauri::Manager;

use crate::probe::Progress;

fn send(ch: &Channel<Progress>, what: &str, done: u64, total: u64, state: &str, msg: Option<String>) {
    let _ = ch.send(Progress {
        what: what.into(),
        done_bytes: done,
        total_bytes: total,
        state: state.into(),
        message: msg,
    });
}

/// Unpack a .tar.gz into `dest`, which is cleared first.
fn untar_gz(archive: &Path, dest: &Path) -> Result<(), String> {
    if dest.exists() {
        std::fs::remove_dir_all(dest).map_err(|e| format!("clear {}: {}", dest.display(), e))?;
    }
    std::fs::create_dir_all(dest).map_err(|e| e.to_string())?;
    let file = std::fs::File::open(archive).map_err(|e| e.to_string())?;
    let mut tarball = tar::Archive::new(flate2::read::GzDecoder::new(file));
    tarball
        .unpack(dest)
        .map_err(|e| format!("unpack {}: {}", archive.display(), e))
}

/// Unpack a .zip into `dest`, which is created but NOT cleared: the llama
/// release splits one directory across two zips (binaries and cudart).
fn unzip(archive: &Path, dest: &Path) -> Result<(), String> {
    std::fs::create_dir_all(dest).map_err(|e| e.to_string())?;
    let file = std::fs::File::open(archive).map_err(|e| e.to_string())?;
    let mut z = zip::ZipArchive::new(file).map_err(|e| e.to_string())?;
    z.extract(dest)
        .map_err(|e| format!("unpack {}: {}", archive.display(), e))
}

/// Unpack an engine archive by extension: the Windows releases are zips with
/// flat contents, the macOS release a tar.gz with a versioned top directory
/// that gets stripped so the binary lands at `dest` directly.
fn unpack_engine(archive: &Path, dest: &Path) -> Result<(), String> {
    let name = archive.to_string_lossy().to_lowercase();
    if name.ends_with(".zip") {
        return unzip(archive, dest);
    }
    let staging = dest.with_extension("unpack");
    untar_gz(archive, &staging)?;
    std::fs::create_dir_all(dest).map_err(|e| e.to_string())?;
    // One top directory: adopt its contents. Anything else: adopt as-is.
    let entries: Vec<_> = std::fs::read_dir(&staging)
        .map_err(|e| e.to_string())?
        .filter_map(|e| e.ok())
        .collect();
    let source = if entries.len() == 1 && entries[0].path().is_dir() {
        entries[0].path()
    } else {
        staging.clone()
    };
    for entry in std::fs::read_dir(&source).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let to = dest.join(entry.file_name());
        if to.exists() {
            let _ = if to.is_dir() {
                std::fs::remove_dir_all(&to)
            } else {
                std::fs::remove_file(&to)
            };
        }
        std::fs::rename(entry.path(), &to).map_err(|e| e.to_string())?;
    }
    let _ = std::fs::remove_dir_all(&staging);
    Ok(())
}

/// The interpreter inside a python-build-standalone tree, per platform.
fn python_in(dir: &Path) -> PathBuf {
    if cfg!(windows) {
        dir.join("python.exe")
    } else {
        dir.join("bin").join("python3")
    }
}

/// The interpreter inside a venv, per platform.
fn venv_python(env_dir: &Path) -> PathBuf {
    if cfg!(windows) {
        env_dir.join("Scripts").join("python.exe")
    } else {
        env_dir.join("bin").join("python")
    }
}

/// The supervisor's file name, matching what pack_backend.sh emits.
fn supervisor_name() -> &'static str {
    if cfg!(windows) { "hearth-supervisor.exe" } else { "hearth-supervisor" }
}

/// The voice engine, built by scripts/build_omnivoice.sh and packed into the
/// bundle beside the supervisor. Shipped rather than installed: nothing is
/// cloned or compiled on a user's machine.
fn tts_server_name() -> &'static str {
    if cfg!(windows) { "tts-server.exe" } else { "tts-server" }
}

/// Fetch one artifact, reporting CUMULATIVE bytes for its row: `base` is what
/// earlier artifacts in the same row already downloaded, `row_total` the
/// row's whole size, so a two-archive row never makes the bar step backward.
fn fetch_artifact(
    a: &RuntimeArtifact,
    cache: &Path,
    row: &str,
    base: u64,
    row_total: u64,
    ch: &Channel<Progress>,
) -> Result<PathBuf, String> {
    let name = a.url.rsplit('/').next().unwrap_or("artifact");
    let name = name.replace("%2B", "+");
    let out = cache.join(&name);
    let row = row.to_string();
    let ch2 = ch.clone();
    let mut report = move |done: u64, _total: u64| {
        let _ = ch2.send(Progress {
            what: row.clone(),
            done_bytes: base + done.min(_total),
            total_bytes: row_total,
            state: "downloading".into(),
            message: None,
        });
    };
    hearth_probe::download::fetch_verified(
        &a.url,
        &out,
        Some(a.bytes),
        a.sha256.as_deref(),
        &mut report,
    )
    .map_err(|e| e.to_string())
}

/// Run a command with output appended to a named log, no console window.
fn run_logged(mut cmd: std::process::Command, logs: &Path, log_name: &str) -> Result<(), String> {
    let log = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(logs.join(log_name))
        .map_err(|e| e.to_string())?;
    cmd.stdout(std::process::Stdio::from(
        log.try_clone().map_err(|e| e.to_string())?,
    ))
    .stderr(std::process::Stdio::from(log));
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    }
    let status = cmd.status().map_err(|e| e.to_string())?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("{} (see logs/{})", status, log_name))
    }
}

const ROW_BACKEND: &str = "The backend";
const ROW_ENGINE: &str = "Inference engine";
const ROW_PYTHON: &str = "Python runtime";
const ROW_VOICE_MODEL: &str = "Voice model";
const ROW_VOICE: &str = "Voice engine";

/// The whole provisioning pass. `accel` is the plan's backend (cuda, vulkan,
/// metal, cpu) and picks the llama assets.
#[tauri::command]
pub async fn provision(
    app: tauri::AppHandle,
    root: String,
    accel: String,
    on_progress: Channel<Progress>,
) -> Result<(), String> {
    let root = PathBuf::from(root.trim());
    if root.as_os_str().is_empty() {
        return Err("no install root".into());
    }
    let backend_tgz = app
        .path()
        .resolve("resources/backend.tar.gz", tauri::path::BaseDirectory::Resource)
        .map_err(|e| e.to_string())?;
    let supervisor_src = app
        .path()
        .resolve(format!("resources/{}", supervisor_name()), tauri::path::BaseDirectory::Resource)
        .map_err(|e| e.to_string())?;
    // Optional: a bundle built without the voice engine installs text-only,
    // the same shape house.rs already allows when the voice row is skipped.
    let tts_server_src = app
        .path()
        .resolve(format!("resources/{}", tts_server_name()), tauri::path::BaseDirectory::Resource)
        .ok()
        .filter(|p| p.is_file());
    let dict = Dictionary::embedded().map_err(|e| e.to_string())?;
    // Which voice engine this platform runs, and therefore whether the voice
    // is a pair of named GGUF files or a Hugging Face snapshot plus a torch
    // environment. The dictionary decides; see `cpp_platforms`.
    let voice_is_cpp = dict.voice.uses_cpp(std::env::consts::OS);

    tauri::async_runtime::spawn_blocking(move || {
        let runtime = root.join("runtime");
        let cache = runtime.join(".cache");
        std::fs::create_dir_all(&cache).map_err(|e| e.to_string())?;
        let logs = root.join("logs");
        let _ = std::fs::create_dir_all(&logs);
        let hf_home = root.join("home").join("hf-cache");

        let result: Result<(), String> = std::thread::scope(|s| {
            // Chain A: the bundled backend and the supervisor. Seconds.
            let ch = on_progress.clone();
            let a_runtime = runtime.clone();
            let a_tgz = backend_tgz.clone();
            let a_sup = supervisor_src.clone();
            let a_tts = tts_server_src.clone();
            let t_backend = s.spawn(move || -> Result<(), String> {
                send(&ch, ROW_BACKEND, 0, 1, "downloading", Some("unpacking".into()));
                untar_gz(&a_tgz, &a_runtime.join("backend")).map_err(|e| {
                    send(&ch, ROW_BACKEND, 0, 1, "failed", Some(e.clone()));
                    e
                })?;
                std::fs::copy(&a_sup, a_runtime.join(supervisor_name()))
                    .map_err(|e| e.to_string())?;
                if let Some(src) = &a_tts {
                    let dst = a_runtime.join(tts_server_name());
                    std::fs::copy(src, &dst).map_err(|e| e.to_string())?;
                    // Tauri's resource copy does not carry the execute bit.
                    #[cfg(unix)]
                    {
                        use std::os::unix::fs::PermissionsExt;
                        let _ = std::fs::set_permissions(&dst, std::fs::Permissions::from_mode(0o755));
                    }
                }
                send(&ch, ROW_BACKEND, 1, 1, "done", None);
                Ok(())
            });

            // Chain B: the inference engine, per the plan's accelerator.
            let ch = on_progress.clone();
            let b_runtime = runtime.clone();
            let b_cache = cache.clone();
            let b_assets = match accel.as_str() {
                "cuda" => dict.runtime.llama_server.windows_cuda.clone(),
                "vulkan" | "cpu" => dict.runtime.llama_server.windows_vulkan.clone(),
                "metal" => dict.runtime.llama_server.macos_metal.clone(),
                other => {
                    let e = format!("no llama-server assets for accelerator '{}'", other);
                    send(&on_progress, ROW_ENGINE, 0, 1, "failed", Some(e.clone()));
                    return Err(e);
                }
            };
            if b_assets.is_empty() {
                let e = format!("dictionary has no llama-server assets for '{}'", accel);
                send(&on_progress, ROW_ENGINE, 0, 1, "failed", Some(e.clone()));
                return Err(e);
            }
            let t_engine = s.spawn(move || -> Result<(), String> {
                let llama_dir = b_runtime.join("llama-server");
                if llama_dir.exists() {
                    std::fs::remove_dir_all(&llama_dir).map_err(|e| e.to_string())?;
                }
                let total: u64 = b_assets.iter().map(|a| a.bytes).sum();
                let mut done: u64 = 0;
                for a in &b_assets {
                    let archive = fetch_artifact(a, &b_cache, ROW_ENGINE, done, total, &ch)
                        .map_err(|e| {
                            send(&ch, ROW_ENGINE, done, total, "failed", Some(e.clone()));
                            e
                        })?;
                    done += a.bytes;
                    send(&ch, ROW_ENGINE, done, total, "verifying", None);
                    unpack_engine(&archive, &llama_dir).map_err(|e| {
                        send(&ch, ROW_ENGINE, done, total, "failed", Some(e.clone()));
                        e
                    })?;
                }
                send(&ch, ROW_ENGINE, total, total, "done", None);
                Ok(())
            });

            // Chain C, main thread: the Python runtime lands first, because
            // both remaining chains need its interpreter.
            let Some(py) = (match std::env::consts::OS {
                "windows" => dict.runtime.python.windows.clone(),
                "macos" => dict.runtime.python.macos.clone(),
                _ => None,
            }) else {
                let e = "dictionary has no python runtime for this platform".to_string();
                send(&on_progress, ROW_PYTHON, 0, 1, "failed", Some(e.clone()));
                return Err(e);
            };
            let name = py.url.rsplit('/').next().unwrap_or("python.tar.gz").replace("%2B", "+");
            let py_out = cache.join(&name);
            let ch2 = on_progress.clone();
            let py_total = py.bytes.max(1);
            let mut py_report = move |done: u64, _t: u64| {
                let _ = ch2.send(Progress {
                    what: ROW_PYTHON.into(),
                    done_bytes: (done.min(py_total) * 70) / py_total,
                    total_bytes: 100,
                    state: "downloading".into(),
                    message: Some("downloading".into()),
                });
            };
            let archive = hearth_probe::download::fetch_verified(
                &py.url,
                &py_out,
                Some(py.bytes),
                py.sha256.as_deref(),
                &mut py_report,
            )
            .map_err(|e| {
                let e = e.to_string();
                send(&on_progress, ROW_PYTHON, 0, 100, "failed", Some(e.clone()));
                e
            })?;
            send(&on_progress, ROW_PYTHON, 75, 100, "downloading", Some("unpacking".into()));
            let staging = runtime.join(".python-unpack");
            untar_gz(&archive, &staging)?;
            let unpacked = staging.join("python");
            let py_dir = runtime.join("python");
            if py_dir.exists() {
                std::fs::remove_dir_all(&py_dir).map_err(|e| e.to_string())?;
            }
            std::fs::rename(&unpacked, &py_dir).map_err(|e| e.to_string())?;
            let _ = std::fs::remove_dir_all(&staging);

            // Fork: the harness requirements then the voice model on one
            // side, the voice engine's environment on the other.
            let ch = on_progress.clone();
            let c_logs = logs.clone();
            let c_runtime = runtime.clone();
            let c_hf = hf_home.clone();
            let c_repo = dict.voice.repo_for(std::env::consts::OS).to_string();
            let c_voice_bytes = dict.voice.download_bytes_for(std::env::consts::OS);
            let c_voice_is_cpp = voice_is_cpp;
            let c_voice_files = dict.voice.files.clone();
            let c_root = root.clone();
            let c_py = py_dir.clone();
            let t_pip_fetch = s.spawn(move || -> Result<(), String> {
                send(&ch, ROW_PYTHON, 85, 100, "downloading", Some("installing packages".into()));
                let requirements = c_runtime.join("backend").join("harness").join("requirements.txt");
                let mut pip = std::process::Command::new(python_in(&c_py));
                pip.args(["-m", "pip", "install", "--no-warn-script-location", "-r"])
                    .arg(&requirements)
                    // The vendored python honors user site-packages by
                    // default, and the developer machine's Roaming packages
                    // shadowed the install's own huggingface_hub. The
                    // product environment is the product's alone.
                    .env("PYTHONNOUSERSITE", "1");
                run_logged(pip, &c_logs, "provision-pip.log").map_err(|e| {
                    send(&ch, ROW_PYTHON, 85, 100, "failed", Some(e.clone()));
                    e
                })?;
                send(&ch, ROW_PYTHON, 100, 100, "done", None);

                send(
                    &ch,
                    ROW_VOICE_MODEL,
                    10,
                    100,
                    "downloading",
                    Some(format!("downloading ({})", hearth_probe::human(c_voice_bytes))),
                );
                if c_voice_is_cpp {
                    // Named files the installer can verify, into the weights
                    // directory with the brain's. The snapshot path below put
                    // them in the Hugging Face cache, which is a cache: right
                    // for something re-fetchable, wrong for something the
                    // install depends on.
                    let dir = c_root.join(hearth_probe::defaults::REL_VOICE_MODELS);
                    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
                    let total: u64 = c_voice_files.iter().map(|f| f.bytes).sum();
                    let mut done: u64 = 0;
                    for f in &c_voice_files {
                        let dest = dir.join(&f.file);
                        let url = hearth_probe::dict::hf_url(&c_repo, &f.file);
                        let ch2 = ch.clone();
                        let base = done;
                        let mut progress = |got: u64, _t: u64| {
                            let pct = ((base + got) as f64 / total.max(1) as f64 * 100.0) as u64;
                            send(&ch2, ROW_VOICE_MODEL, pct.min(99), 100, "downloading", None);
                        };
                        hearth_probe::download::fetch_verified(
                            &url,
                            &dest,
                            Some(f.bytes),
                            f.sha256.as_deref(),
                            &mut progress,
                        )
                        .map_err(|e| {
                            let e = e.to_string();
                            send(&ch2, ROW_VOICE_MODEL, 10, 100, "failed", Some(e.clone()));
                            e
                        })?;
                        done += f.bytes;
                    }
                } else {
                    let mut prefetch = std::process::Command::new(python_in(&c_py));
                    prefetch
                        .args(["-c"])
                        .arg(format!(
                            "from huggingface_hub import snapshot_download; snapshot_download('{}')",
                            c_repo
                        ))
                        .env("HF_HOME", &c_hf)
                        .env("PYTHONNOUSERSITE", "1")
                        // Symlinks need Developer Mode on Windows (WinError 1314
                        // on a stranger's machine, found the honest way).
                        .env("HF_HUB_DISABLE_SYMLINKS", "1");
                    run_logged(prefetch, &c_logs, "provision-voice-fetch.log").map_err(|e| {
                        send(&ch, ROW_VOICE_MODEL, 10, 100, "failed", Some(e.clone()));
                        e
                    })?;
                }
                send(&ch, ROW_VOICE_MODEL, 100, 100, "done", None);
                Ok(())
            });

            let ch = on_progress.clone();
            let d_logs = logs.clone();
            let d_root = root.clone();
            let d_py = py_dir.clone();
            let d_env = dict.runtime.voice_env.clone();
            let d_accel = accel.clone();
            let d_voice_is_cpp = voice_is_cpp;
            let t_voice = s.spawn(move || -> Result<(), String> {
                // The C++ engine ships as a binary and needs no Python at all.
                // This whole chain -- a venv, torch, and the engine package --
                // was the slowest and most failure-prone part of an install,
                // and on a platform running omnivoice.cpp it simply does not
                // happen. Roughly 1.3 GiB of environment that stops existing.
                if d_voice_is_cpp {
                    send(&ch, ROW_VOICE, 100, 100, "done", Some("engine ships with Hearth".into()));
                    return Ok(());
                }
                let voice_py = venv_python(&d_root.join("envs").join("voice"));
                send(&ch, ROW_VOICE, 10, 100, "downloading", Some("creating environment".into()));
                let mut mkenv = std::process::Command::new(python_in(&d_py));
                mkenv.args(["-m", "venv"]).arg(d_root.join("envs").join("voice"));
                run_logged(mkenv, &d_logs, "provision-voice-pip.log").map_err(|e| {
                    send(&ch, ROW_VOICE, 10, 100, "failed", Some(e.clone()));
                    e
                })?;

                send(&ch, ROW_VOICE, 25, 100, "downloading", Some("installing torch".into()));
                let mut torch = std::process::Command::new(&voice_py);
                torch.args(["-m", "pip", "install", "--no-warn-script-location", "torch", "torchaudio"]);
                if d_accel == "cuda" {
                    if let Some(index) = &d_env.torch_index_cuda {
                        torch.args(["--index-url", index]);
                    }
                }
                run_logged(torch, &d_logs, "provision-voice-pip.log").map_err(|e| {
                    send(&ch, ROW_VOICE, 25, 100, "failed", Some(e.clone()));
                    e
                })?;

                send(&ch, ROW_VOICE, 70, 100, "downloading", Some("installing the engine".into()));
                let mut engine = std::process::Command::new(&voice_py);
                engine.args(["-m", "pip", "install", "--no-warn-script-location"]);
                engine.arg(&d_env.package);
                for extra in &d_env.extras {
                    engine.arg(extra);
                }
                run_logged(engine, &d_logs, "provision-voice-pip.log").map_err(|e| {
                    send(&ch, ROW_VOICE, 70, 100, "failed", Some(e.clone()));
                    e
                })?;
                send(&ch, ROW_VOICE, 100, 100, "done", None);
                Ok(())
            });

            // Every chain must land; the first error is the one reported,
            // and its row already wears the message.
            for handle in [t_backend, t_engine, t_pip_fetch, t_voice] {
                handle.join().map_err(|_| "a provisioning thread panicked".to_string())??;
            }
            Ok(())
        });

        result?;
        let _ = std::fs::remove_dir_all(&cache);
        Ok(())
    })
    .await
    .map_err(|e| e.to_string())?
}
