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

/// Fetch everything the plan asks for, reporting progress, verifying each
/// file's sha256 where the dictionary carries one, and writing the install
/// record beside the weights when everything has landed.
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
    let dir = dest
        .clone()
        .filter(|d| !d.trim().is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(machine::default_model_dir);
    // The plan the record keeps must be the plan the user saw, so the same
    // dest-aware free-disk override probe_plan applies happens here too.
    if simulate.is_none() {
        m.free_disk_bytes = machine::free_disk_for(&dir);
    }
    let d = Dictionary::embedded().map_err(|e| e.to_string())?;
    let p = plan(&m, &d).map_err(|e| e.to_string())?;

    tauri::async_runtime::spawn_blocking(move || {
        let mut landed = Vec::new();
        for item in &p.downloads {
            let Some(url) = item.url.clone() else {
                let _ = on_progress.send(Progress {
                    what: item.what.clone(),
                    done_bytes: 0,
                    total_bytes: item.bytes,
                    state: "skipped".into(),
                    message: Some("fetched by the runtime on first use".into()),
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
            "version": 1,
            "completed_unix": std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|t| t.as_secs())
                .unwrap_or(0),
            "machine": &m,
            "plan": &p,
            "weights_dir": dir.to_string_lossy(),
            "landed": &landed,
        });
        let record_path = dir.join("hearth-install.json");
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
        }

        Ok(landed)
    })
    .await
    .map_err(|e| e.to_string())?
}
