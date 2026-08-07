//! Provisioning: everything the installing screen places besides the models.
//!
//! Three rows, run while the model downloads: the backend (bundled with the
//! client, unpacked), the inference engine (llama.cpp release assets, chosen
//! by the plan's accelerator, downloaded and verified like a model), and the
//! Python runtime (python-build-standalone, then the harness requirements
//! installed into it). Every artifact's source, size and hash live in the
//! dictionary; nothing here names a URL.
//!
//! Idempotent by construction: fetches skip files already at exact size,
//! and unpacks clear their target first. Retry is rerun.

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
        .resolve("resources/hearth-supervisor.exe", tauri::path::BaseDirectory::Resource)
        .map_err(|e| e.to_string())?;
    let dict = Dictionary::embedded().map_err(|e| e.to_string())?;

    tauri::async_runtime::spawn_blocking(move || {
        let runtime = root.join("runtime");
        let cache = runtime.join(".cache");
        std::fs::create_dir_all(&cache).map_err(|e| e.to_string())?;

        // Row 1: the backend, bundled with the client.
        const ROW_BACKEND: &str = "The backend";
        send(&on_progress, ROW_BACKEND, 0, 1, "downloading", Some("unpacking".into()));
        untar_gz(&backend_tgz, &runtime.join("backend")).map_err(|e| {
            send(&on_progress, ROW_BACKEND, 0, 1, "failed", Some(e.clone()));
            e
        })?;
        std::fs::copy(&supervisor_src, runtime.join("hearth-supervisor.exe"))
            .map_err(|e| e.to_string())?;
        send(&on_progress, ROW_BACKEND, 1, 1, "done", None);

        // Row 2: the inference engine, per the plan's accelerator.
        const ROW_ENGINE: &str = "Inference engine";
        let assets = match accel.as_str() {
            "cuda" => &dict.runtime.llama_server.windows_cuda,
            "vulkan" | "cpu" => &dict.runtime.llama_server.windows_vulkan,
            "metal" => &dict.runtime.llama_server.macos_metal,
            other => {
                let e = format!("no llama-server assets for accelerator '{}'", other);
                send(&on_progress, ROW_ENGINE, 0, 1, "failed", Some(e.clone()));
                return Err(e);
            }
        };
        if assets.is_empty() {
            let e = format!("dictionary has no llama-server assets for '{}'", accel);
            send(&on_progress, ROW_ENGINE, 0, 1, "failed", Some(e.clone()));
            return Err(e);
        }
        let llama_dir = runtime.join("llama-server");
        if llama_dir.exists() {
            std::fs::remove_dir_all(&llama_dir).map_err(|e| e.to_string())?;
        }
        let engine_total: u64 = assets.iter().map(|a| a.bytes).sum();
        let mut engine_done: u64 = 0;
        for a in assets {
            let archive = fetch_artifact(a, &cache, ROW_ENGINE, engine_done, engine_total, &on_progress)
                .map_err(|e| {
                    send(&on_progress, ROW_ENGINE, engine_done, engine_total, "failed", Some(e.clone()));
                    e
                })?;
            engine_done += a.bytes;
            send(&on_progress, ROW_ENGINE, engine_done, engine_total, "verifying", None);
            unzip(&archive, &llama_dir).map_err(|e| {
                send(&on_progress, ROW_ENGINE, engine_done, engine_total, "failed", Some(e.clone()));
                e
            })?;
        }
        send(&on_progress, ROW_ENGINE, engine_total, engine_total, "done", None);

        // Row 3: the Python runtime, then the harness requirements into it.
        const ROW_PYTHON: &str = "Python runtime";
        let Some(py) = (match std::env::consts::OS {
            "windows" => dict.runtime.python.windows.clone(),
            "macos" => dict.runtime.python.macos.clone(),
            _ => None,
        }) else {
            let e = "dictionary has no python runtime for this platform".to_string();
            send(&on_progress, ROW_PYTHON, 0, 1, "failed", Some(e.clone()));
            return Err(e);
        };
        /* This row is download plus unpack plus a pip resolve, so it reports
           on a percent scale that only moves forward: the download is the
           first seventy points, the pip install the rest. The message names
           the phase; the numbers feed the weighted bar. */
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
        // The tarball's top directory is python/; unpack beside it and adopt.
        let staging = runtime.join(".python-unpack");
        untar_gz(&archive, &staging)?;
        let unpacked = staging.join("python");
        let target = runtime.join("python");
        if target.exists() {
            std::fs::remove_dir_all(&target).map_err(|e| e.to_string())?;
        }
        std::fs::rename(&unpacked, &target).map_err(|e| e.to_string())?;
        let _ = std::fs::remove_dir_all(&staging);

        send(
            &on_progress,
            ROW_PYTHON,
            85,
            100,
            "downloading",
            Some("installing packages".into()),
        );
        let logs = root.join("logs");
        let _ = std::fs::create_dir_all(&logs);
        let pip_log = std::fs::File::create(logs.join("provision-pip.log"))
            .map_err(|e| e.to_string())?;
        let requirements = runtime.join("backend").join("harness").join("requirements.txt");
        let mut cmd = std::process::Command::new(target.join("python.exe"));
        cmd.args([
            "-m",
            "pip",
            "install",
            "--no-warn-script-location",
            "-r",
        ])
        .arg(&requirements)
        .stdout(std::process::Stdio::from(
            pip_log.try_clone().map_err(|e| e.to_string())?,
        ))
        .stderr(std::process::Stdio::from(pip_log));
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
        }
        let status = cmd.status().map_err(|e| e.to_string())?;
        if !status.success() {
            let e = format!(
                "pip install failed ({}); see logs/provision-pip.log",
                status
            );
            send(&on_progress, ROW_PYTHON, 0, 1, "failed", Some(e.clone()));
            return Err(e);
        }
        send(&on_progress, ROW_PYTHON, 100, 100, "done", None);

        // Row 4: the voice engine, in its own environment. The heaviest row
        // and the one that lets Sulivan speak at the end of the install.
        const ROW_VOICE: &str = "Voice engine";
        let run_logged = |mut cmd: std::process::Command, log_name: &str| -> Result<(), String> {
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
                cmd.creation_flags(0x0800_0000);
            }
            let status = cmd.status().map_err(|e| e.to_string())?;
            if status.success() {
                Ok(())
            } else {
                Err(format!("{} (see logs/{})", status, log_name))
            }
        };

        let voice_py = root
            .join("envs")
            .join("voice")
            .join("Scripts")
            .join("python.exe");
        send(&on_progress, ROW_VOICE, 5, 100, "downloading", Some("creating environment".into()));
        let mut mkenv = std::process::Command::new(target.join("python.exe"));
        mkenv.args(["-m", "venv"]).arg(root.join("envs").join("voice"));
        run_logged(mkenv, "provision-voice-pip.log").map_err(|e| {
            send(&on_progress, ROW_VOICE, 0, 1, "failed", Some(e.clone()));
            e
        })?;

        send(&on_progress, ROW_VOICE, 15, 100, "downloading", Some("installing torch".into()));
        let mut torch = std::process::Command::new(&voice_py);
        torch.args(["-m", "pip", "install", "--no-warn-script-location", "torch", "torchaudio"]);
        if accel == "cuda" {
            if let Some(index) = &dict.runtime.voice_env.torch_index_cuda {
                torch.args(["--index-url", index]);
            }
        }
        run_logged(torch, "provision-voice-pip.log").map_err(|e| {
            send(&on_progress, ROW_VOICE, 0, 1, "failed", Some(e.clone()));
            e
        })?;

        send(&on_progress, ROW_VOICE, 55, 100, "downloading", Some("installing the engine".into()));
        let mut engine = std::process::Command::new(&voice_py);
        engine.args(["-m", "pip", "install", "--no-warn-script-location"]);
        engine.arg(&dict.runtime.voice_env.package);
        for extra in &dict.runtime.voice_env.extras {
            engine.arg(extra);
        }
        run_logged(engine, "provision-voice-pip.log").map_err(|e| {
            send(&on_progress, ROW_VOICE, 0, 1, "failed", Some(e.clone()));
            e
        })?;

        send(
            &on_progress,
            ROW_VOICE,
            70,
            100,
            "downloading",
            Some(format!("fetching the voice ({})", hearth_probe::human(dict.voice.download_bytes))),
        );
        let mut prefetch = std::process::Command::new(&voice_py);
        prefetch
            .args(["-c"])
            .arg(format!(
                "from huggingface_hub import snapshot_download; snapshot_download('{}')",
                dict.voice.repo
            ))
            .env("HF_HOME", root.join("home").join("hf-cache"))
            // Symlinks need Developer Mode on Windows (WinError 1314 on a
            // stranger's machine, found the honest way). A per-install cache
            // holds one model; duplicated plain files cost nothing.
            .env("HF_HUB_DISABLE_SYMLINKS", "1");
        run_logged(prefetch, "provision-voice-fetch.log").map_err(|e| {
            send(&on_progress, ROW_VOICE, 0, 1, "failed", Some(e.clone()));
            e
        })?;
        send(&on_progress, ROW_VOICE, 100, 100, "done", None);

        let _ = std::fs::remove_dir_all(&cache);
        Ok(())
    })
    .await
    .map_err(|e| e.to_string())?
}
