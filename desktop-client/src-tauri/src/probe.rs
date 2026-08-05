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
#[tauri::command]
pub fn probe_plan(simulate: Option<String>) -> Result<plan::Plan, String> {
    let m = machine_for(simulate)?;
    let d = Dictionary::embedded().map_err(|e| e.to_string())?;
    plan(&m, &d).map_err(|e| e.to_string())
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

/// Fetch everything the plan asks for, reporting progress.
///
/// Runs on a blocking thread: the transfer is synchronous and multi-gigabyte,
/// and it must not sit on the UI runtime.
#[tauri::command]
pub async fn probe_download(
    simulate: Option<String>,
    dest: Option<String>,
    on_progress: Channel<Progress>,
) -> Result<Vec<String>, String> {
    let m = machine_for(simulate)?;
    let d = Dictionary::embedded().map_err(|e| e.to_string())?;
    let p = plan(&m, &d).map_err(|e| e.to_string())?;
    let dir = dest
        .map(PathBuf::from)
        .unwrap_or_else(machine::default_model_dir);

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

            match hearth_probe::download::fetch_with(&url, &out, Some(item.bytes), &mut report) {
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
        Ok(landed)
    })
    .await
    .map_err(|e| e.to_string())?
}
