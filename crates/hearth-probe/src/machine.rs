//! What is physically here.
//!
//! This module is the only one that touches the machine. Everything it learns
//! goes into `Machine`, which serializes to JSON, which means a tester can send
//! us their machine and we can reproduce their plan exactly.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Gpu {
    /// "nvidia" | "apple" | "unknown"
    pub vendor: String,
    pub name: String,
    /// Dedicated video memory. None when memory is unified with the host.
    pub vram_bytes: Option<u64>,
    /// NVIDIA compute capability, e.g. "8.9". This is what the CUDA build
    /// architecture is derived from; it is hardcoded to 89 today.
    pub compute_cap: Option<String>,
    pub driver: Option<String>,
    /// "cuda" | "metal" | "cpu"
    pub backend: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Machine {
    pub os: String,
    pub arch: String,
    pub cpu_cores: usize,
    pub ram_bytes: u64,
    /// Free space on the volume Hearth would install to. On Windows this is
    /// deliberately the WINDOWS volume: inside WSL the root filesystem reports
    /// far more free space than the host actually has, because the distro disk
    /// is a growing virtual disk on C:. Believing the inside number is how a
    /// model copy took the whole VM down once.
    pub free_disk_bytes: u64,
    pub gpu: Option<Gpu>,
    /// True on Apple Silicon, where the GPU and the host share one pool and the
    /// budget arithmetic has to subtract the operating system.
    pub unified_memory: bool,
    /// Windows only. None elsewhere.
    pub wsl_present: Option<bool>,
    /// Set when this Machine came from --simulate rather than from hardware.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub simulated: Option<String>,
}

impl Machine {
    /// Memory the planner gets to spend from, before reservations.
    pub fn memory_pool(&self) -> u64 {
        match self.gpu.as_ref().and_then(|g| g.vram_bytes) {
            Some(vram) => vram,
            None => self.ram_bytes,
        }
    }

    pub fn backend(&self) -> &str {
        self.gpu.as_ref().map(|g| g.backend.as_str()).unwrap_or("cpu")
    }
}

pub fn scan() -> Result<Machine> {
    let mut sys = sysinfo::System::new();
    sys.refresh_memory();

    let os = std::env::consts::OS.to_string();
    let arch = std::env::consts::ARCH.to_string();
    let ram_bytes = sys.total_memory();
    // std rather than sysinfo: the core-count API moved between sysinfo
    // versions and this number is not worth a version pin.
    let cpu_cores = std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(0);

    let unified_memory = os == "macos" && arch == "aarch64";
    let gpu = detect_gpu(&os, unified_memory, ram_bytes);
    let wsl_present = if os == "windows" { Some(detect_wsl()) } else { None };

    Ok(Machine {
        os,
        arch,
        cpu_cores,
        ram_bytes,
        free_disk_bytes: free_disk_for(&default_model_dir()),
        gpu,
        unified_memory,
        wsl_present,
        simulated: None,
    })
}

fn detect_gpu(os: &str, unified: bool, ram_bytes: u64) -> Option<Gpu> {
    if unified {
        return Some(Gpu {
            vendor: "apple".into(),
            name: apple_chip().unwrap_or_else(|| "Apple Silicon".into()),
            // Deliberately None. Unified memory is not video memory, and
            // pretending otherwise is what produces a plan that will not load.
            vram_bytes: None,
            compute_cap: None,
            driver: None,
            backend: "metal".into(),
        });
    }
    if let Some(g) = nvidia() {
        return Some(g);
    }
    let _ = (os, ram_bytes);
    None
}

/// NVIDIA, via nvidia-smi and never via WMI.
///
/// `Win32_VideoController.AdapterRAM` reports 4 GB for a 16 GB card because the
/// field is 32-bit and overflows. That is recorded in the 2026-08-04 audit and
/// it is the single easiest way to get this wrong.
fn nvidia() -> Option<Gpu> {
    let out = Command::new("nvidia-smi")
        .args([
            "--query-gpu=name,memory.total,compute_cap,driver_version",
            "--format=csv,noheader,nounits",
        ])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let line = text.lines().next()?;
    let f: Vec<&str> = line.split(',').map(|s| s.trim()).collect();
    if f.len() < 4 {
        return None;
    }
    // nvidia-smi reports MiB.
    let vram = f[1].parse::<u64>().ok()? * 1024 * 1024;
    Some(Gpu {
        vendor: "nvidia".into(),
        name: f[0].to_string(),
        vram_bytes: Some(vram),
        compute_cap: Some(f[2].to_string()),
        driver: Some(f[3].to_string()),
        backend: "cuda".into(),
    })
}

fn apple_chip() -> Option<String> {
    let out = Command::new("sysctl")
        .args(["-n", "machdep.cpu.brand_string"])
        .output()
        .ok()?;
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if s.is_empty() {
        None
    } else {
        Some(s)
    }
}

/// One call. Never a poll.
///
/// Repeated one-off `wsl.exe` invocations bounce the systemd user manager and
/// restart the resident model. That cost this project a day in June.
fn detect_wsl() -> bool {
    Command::new("wsl.exe")
        .args(["-l", "-q"])
        .output()
        .map(|o| o.status.success() && !o.stdout.is_empty())
        .unwrap_or(false)
}

/// Free space on the volume the weights would actually land on.
///
/// Taking the largest disk on the machine is WRONG and was a real bug here:
/// run inside WSL it picked the distro's own filesystem, which reports the
/// virtual disk's maximum size rather than the space the host can actually
/// give it. That is exactly the trap in the audit, reproduced by the code
/// written to avoid it.
///
/// The right answer is the volume containing the install path: the disk whose
/// mount point is the longest prefix of it. Public because the destination is
/// the user's to change, and the number on screen has to follow their choice.
pub fn free_disk_for(target: &Path) -> u64 {
    let disks = sysinfo::Disks::new_with_refreshed_list();
    let mut best: Option<(usize, u64)> = None;
    for d in disks.list() {
        let mp = d.mount_point();
        if target.starts_with(mp) {
            let depth = mp.components().count();
            if best.map(|(bd, _)| depth > bd).unwrap_or(true) {
                best = Some((depth, d.available_space()));
            }
        }
    }
    best.map(|(_, free)| free).unwrap_or(0)
}

/// Where models land by default, and therefore the volume that matters.
///
/// On Windows the default deliberately avoids the system drive: weights are
/// tens of gigabytes, the system drive is the one volume whose exhaustion
/// takes the machine down with it, and a home directory default lands there
/// every time. So the default is `Hearth\models` on the roomiest fixed drive
/// that is not the system one, and the home directory is only the fallback for
/// a single-drive machine. The user can still choose anywhere; this is only
/// where the box starts.
///
/// Note the tension this sits in: weights must live on the Linux-native
/// filesystem for load speed, because the same file on the Windows mount takes
/// minutes to load and can exceed the model swap timeout. But that filesystem
/// is a growing virtual disk on the system drive, so choosing speed spends
/// system-drive space. The install check has to look at the volume backing the
/// distro, not at the roomiest disk in the machine.
pub fn default_model_dir() -> PathBuf {
    default_install_root().join("models")
}

/// The one folder Hearth lives under: models, configuration, the install
/// record, and eventually the WSL distro's own disk. Deleting it (plus the
/// distro unregister) IS the uninstall, so nothing of the product may land
/// outside it.
pub fn default_install_root() -> PathBuf {
    if std::env::consts::OS == "windows" {
        if let Some(root) = roomiest_non_system_drive() {
            return root.join("Hearth");
        }
    }
    if let Some(home) = std::env::var_os("HOME").or_else(|| std::env::var_os("USERPROFILE")) {
        return PathBuf::from(home).join(".hearth");
    }
    PathBuf::from(".hearth")
}

/// The fixed drive with the most free space, excluding the system drive.
/// None on a single-drive machine, which is what routes the default back to
/// the home directory.
fn roomiest_non_system_drive() -> Option<PathBuf> {
    let system_root = std::env::var_os("SystemDrive")
        .map(|d| PathBuf::from(format!("{}\\", d.to_string_lossy())));
    let disks = sysinfo::Disks::new_with_refreshed_list();
    disks
        .list()
        .iter()
        .filter(|d| !d.is_removable())
        .filter(|d| {
            system_root
                .as_ref()
                .map(|s| d.mount_point() != s.as_path())
                .unwrap_or(true)
        })
        .max_by_key(|d| d.available_space())
        .map(|d| d.mount_point().to_path_buf())
}

/// Fixtures, so a low-end machine can be tested from a machine that is not one.
pub fn simulated(name: &str) -> Option<Machine> {
    let m = match name {
        // VYTAL as measured 2026-08-04.
        "rtx4080" => Machine {
            os: "windows".into(),
            arch: "x86_64".into(),
            cpu_cores: 16,
            ram_bytes: 34_010_000_000,
            free_disk_bytes: 330_000_000_000,
            gpu: Some(Gpu {
                vendor: "nvidia".into(),
                name: "NVIDIA GeForce RTX 4080".into(),
                vram_bytes: Some(16376 * 1024 * 1024),
                compute_cap: Some("8.9".into()),
                driver: Some("580.00".into()),
                backend: "cuda".into(),
            }),
            unified_memory: false,
            wsl_present: Some(true),
            simulated: Some("rtx4080".into()),
        },
        // The M1 Air. The machine tier 0 exists for.
        "m1-air-8gb" => Machine {
            os: "macos".into(),
            arch: "aarch64".into(),
            cpu_cores: 8,
            ram_bytes: 8 * 1024 * 1024 * 1024,
            free_disk_bytes: 64 * 1024 * 1024 * 1024,
            gpu: Some(Gpu {
                vendor: "apple".into(),
                name: "Apple M1".into(),
                vram_bytes: None,
                compute_cap: None,
                driver: None,
                backend: "metal".into(),
            }),
            unified_memory: true,
            wsl_present: None,
            simulated: Some("m1-air-8gb".into()),
        },
        "m1-air-16gb" => Machine {
            os: "macos".into(),
            arch: "aarch64".into(),
            cpu_cores: 8,
            ram_bytes: 16 * 1024 * 1024 * 1024,
            free_disk_bytes: 200 * 1024 * 1024 * 1024,
            gpu: Some(Gpu {
                vendor: "apple".into(),
                name: "Apple M1".into(),
                vram_bytes: None,
                compute_cap: None,
                driver: None,
                backend: "metal".into(),
            }),
            unified_memory: true,
            wsl_present: None,
            simulated: Some("m1-air-16gb".into()),
        },
        // No GPU at all. Must produce a plan or an honest refusal, never a panic.
        "no-gpu" => Machine {
            os: "windows".into(),
            arch: "x86_64".into(),
            cpu_cores: 4,
            ram_bytes: 16 * 1024 * 1024 * 1024,
            free_disk_bytes: 120 * 1024 * 1024 * 1024,
            gpu: None,
            unified_memory: false,
            wsl_present: Some(false),
            simulated: Some("no-gpu".into()),
        },
        // Below the floor. "It will not run here" is a legitimate answer.
        "tiny" => Machine {
            os: "windows".into(),
            arch: "x86_64".into(),
            cpu_cores: 2,
            ram_bytes: 4 * 1024 * 1024 * 1024,
            free_disk_bytes: 20 * 1024 * 1024 * 1024,
            gpu: None,
            unified_memory: false,
            wsl_present: Some(false),
            simulated: Some("tiny".into()),
        },
        _ => return None,
    };
    Some(m)
}

pub const FIXTURES: &[&str] = &["rtx4080", "m1-air-8gb", "m1-air-16gb", "no-gpu", "tiny"];
