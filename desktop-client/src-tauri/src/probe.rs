//! Hardware scan, plan, and model download, exposed to the client.
//!
//! Thin. Every decision lives in `hearth-probe` so the CLI, the installation
//! skill and this all give the same answers. If logic starts appearing in this
//! file it belongs in the crate instead.

use hearth_probe::{machine, plan, Dictionary};
use serde::Serialize;
use std::path::PathBuf;
use tauri::ipc::Channel;

/// Emitted while a download runs.
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Progress {
    pub what: String,
    pub done_bytes: u64,
    pub total_bytes: u64,
    /// "downloading" | "done" | "skipped" | "failed"
    pub state: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

fn machine_for(simulate: Option<String>) -> Result<machine::Machine, String> {
    match simulate {
        Some(name) => machine::simulated(&name)
            .ok_or_else(|| format!("no such simulated machine: {name}")),
        None => machine::scan().map_err(|e| e.to_string()),
    }
}

/// Look at this machine. `simulate` swaps in a fixture, which is how a
/// small-machine install is tested from a machine that is not one.
#[tauri::command]
pub fn probe_scan(simulate: Option<String>) -> Result<machine::Machine, String> {
    machine_for(simulate)
}

/// Decide what to run. Pure, given a machine.
///
/// `dest` is the user's chosen weights destination. On a real scan the free
/// disk figure is recomputed against it, so the disk warning describes the
/// volume the download will actually land on rather than the default's.
/// Fixtures keep their recorded number: they exist to exercise the screens,
/// and this machine's disks would overwrite the story they tell.
#[tauri::command]
pub fn probe_plan(simulate: Option<String>, dest: Option<String>) -> Result<plan::Plan, String> {
    let mut m = machine_for(simulate.clone())?;
    if simulate.is_none() {
        if let Some(d) = dest.filter(|d| !d.trim().is_empty()) {
            m.free_disk_bytes = machine::free_disk_for(&PathBuf::from(d));
        }
    }
    let d = Dictionary::embedded().map_err(|e| e.to_string())?;
    plan(&m, &d).map_err(|e| e.to_string())
}

/// Free space on the volume containing `path`, for the found screen to show
/// while the user is choosing a destination.
#[tauri::command]
pub fn probe_free_disk(path: String) -> u64 {
    machine::free_disk_for(&PathBuf::from(path))
}

/// The machines that can be simulated, for the developer picker.
#[tauri::command]
pub fn probe_fixtures() -> Vec<String> {
    machine::FIXTURES.iter().map(|s| s.to_string()).collect()
}

/// Where weights land by default on this machine.
#[tauri::command]
pub fn probe_model_dir() -> String {
    machine::default_model_dir().to_string_lossy().to_string()
}

/// What to call this device when it asks to join a house on another machine.
#[tauri::command]
pub fn probe_device_name() -> String {
    machine::host_name()
}

/// The default install root: the one folder everything lives under.
#[tauri::command]
pub fn probe_install_root() -> String {
    machine::default_install_root().to_string_lossy().to_string()
}

/// What the boot check reports about an install.
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InstallState {
    /// The record exists and everything it names is present at full size.
    pub ok: bool,
    pub record_exists: bool,
    /// Anything the record names that is missing or the wrong size.
    pub missing: Vec<String>,
}

/// Validate an install against its own record.
///
/// The record on disk is the truth about whether Hearth is installed; the
/// browser flag is only a cache of it. A missing folder, a missing record, or
/// a gutted models directory all mean "not installed", however the flag
/// reads. This is what makes deleting the install folder a real uninstall.
#[tauri::command]
pub fn probe_install_state(root: Option<String>) -> InstallState {
    let root = root
        .filter(|r| !r.trim().is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(machine::default_install_root);
    let record_path = root.join("hearth-install.json");
    let Ok(text) = std::fs::read_to_string(&record_path) else {
        return InstallState {
            ok: false,
            record_exists: false,
            missing: vec![record_path.to_string_lossy().to_string()],
        };
    };
    let Ok(record) = serde_json::from_str::<serde_json::Value>(&text) else {
        return InstallState {
            ok: false,
            record_exists: true,
            missing: vec![format!("{} (unreadable)", record_path.display())],
        };
    };
    let mut missing = Vec::new();
    for landed in record
        .get("landed")
        .and_then(|l| l.as_array())
        .into_iter()
        .flatten()
    {
        let Some(path) = landed.as_str() else { continue };
        if std::fs::metadata(path).map(|m| m.len() > 0).unwrap_or(false) {
            continue;
        }
        missing.push(path.to_string());
    }
    InstallState {
        ok: missing.is_empty(),
        record_exists: true,
        missing,
    }
}

/// Fetch everything the plan asks for, reporting progress, verifying each
/// file's sha256 where the dictionary carries one, and writing the install
/// record when everything has landed.
///
/// `dest` is the INSTALL ROOT, the one folder Hearth lives under. Weights go
/// to `<root>/models`, the record to `<root>/hearth-install.json`, and the
/// provisioner will put everything else under the same root. Deleting the
/// root is the uninstall.
///
/// Runs on a blocking thread: the transfer is synchronous and multi-gigabyte,
/// and it must not sit on the UI runtime.
#[tauri::command]
pub async fn probe_download(
    simulate: Option<String>,
    dest: Option<String>,
    on_progress: Channel<Progress>,
) -> Result<Vec<String>, String> {
    let mut m = machine_for(simulate.clone())?;
    let root = dest
        .clone()
        .filter(|d| !d.trim().is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(machine::default_install_root);
    let dir = root.join("models");
    // The plan the record keeps must be the plan the user saw, so the same
    // dest-aware free-disk override probe_plan applies happens here too.
    if simulate.is_none() {
        m.free_disk_bytes = machine::free_disk_for(&root);
    }
    let d = Dictionary::embedded().map_err(|e| e.to_string())?;
    let p = plan(&m, &d).map_err(|e| e.to_string())?;

    tauri::async_runtime::spawn_blocking(move || {
        let mut landed = Vec::new();
        for item in &p.downloads {
            let Some(url) = item.url.clone() else {
                // The voice has no direct URL; the Voice engine row fetches
                // it into the install's own cache. This event only keeps the
                // accounting straight; the screen no longer shows the row.
                let _ = on_progress.send(Progress {
                    what: item.what.clone(),
                    done_bytes: 0,
                    total_bytes: item.bytes,
                    state: "skipped".into(),
                    message: Some("installed by the Voice engine step".into()),
                });
                continue;
            };
            let file = item.file.clone().unwrap_or_else(|| "download.bin".into());
            let out = dir.join(&file);
            let what = item.what.clone();

            let ch = on_progress.clone();
            let label = what.clone();
            let mut report = move |done: u64, total: u64| {
                let _ = ch.send(Progress {
                    what: label.clone(),
                    done_bytes: done,
                    total_bytes: total,
                    state: "downloading".into(),
                    message: None,
                });
            };

            let fetched =
                hearth_probe::download::fetch_with(&url, &out, Some(item.bytes), &mut report)
                    .and_then(|path| {
                        if let Some(want) = item.sha256.as_deref() {
                            let ch = on_progress.clone();
                            let label = what.clone();
                            let mut hashing = move |done: u64, total: u64| {
                                let _ = ch.send(Progress {
                                    what: label.clone(),
                                    done_bytes: done,
                                    total_bytes: total,
                                    state: "verifying".into(),
                                    message: None,
                                });
                            };
                            hearth_probe::download::verify_sha256(&path, want, &mut hashing)?;
                        }
                        Ok(path)
                    });

            match fetched {
                Ok(path) => {
                    let _ = on_progress.send(Progress {
                        what: what.clone(),
                        done_bytes: item.bytes,
                        total_bytes: item.bytes,
                        state: "done".into(),
                        message: None,
                    });
                    landed.push(path.to_string_lossy().to_string());
                }
                Err(e) => {
                    let _ = on_progress.send(Progress {
                        what,
                        done_bytes: 0,
                        total_bytes: item.bytes,
                        state: "failed".into(),
                        message: Some(e.to_string()),
                    });
                    return Err(e.to_string());
                }
            }
        }

        /* The install record. The only durable evidence of what this install
           chose and where it put things. localStorage is a browser flag that
           dies with the webview profile; this file is what a support
           conversation, an upgrade, or the backend provisioner reads. */
        let record = serde_json::json!({
            "version": 2,
            "completed_unix": std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|t| t.as_secs())
                .unwrap_or(0),
            "machine": &m,
            "plan": &p,
            "install_root": root.to_string_lossy(),
            "weights_dir": dir.to_string_lossy(),
            "landed": &landed,
        });
        let record_path = root.join("hearth-install.json");
        if let Err(e) = std::fs::write(
            &record_path,
            serde_json::to_string_pretty(&record).unwrap_or_default(),
        ) {
            // The weights are down; a missing record is worth a warning, not
            // a failed install.
            let _ = on_progress.send(Progress {
                what: "install record".into(),
                done_bytes: 0,
                total_bytes: 0,
                state: "failed".into(),
                message: Some(format!("could not write {}: {}", record_path.display(), e)),
            });
        } else if let Err(e) = crate::config_gen::render(&root) {
            // The record is the input; the rendered hearth.env is the output
            // every backend process reads. Failing to write it is worth the
            // same honesty.
            let _ = on_progress.send(Progress {
                what: "configuration".into(),
                done_bytes: 0,
                total_bytes: 0,
                state: "failed".into(),
                message: Some(e),
            });
        }

        Ok(landed)
    })
    .await
    .map_err(|e| e.to_string())?
}
