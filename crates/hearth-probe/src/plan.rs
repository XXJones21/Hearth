//! What this machine should run.
//!
//! PURE. No I/O, no environment, no clock. Same `Machine` plus same
//! `Dictionary` always yields the same `Plan`. That is what makes the budget
//! arithmetic testable against fixtures instead of needing four computers.

use crate::dict::{hf_url, Dictionary, Tier};
use crate::machine::Machine;
use crate::human;
use serde::{Deserialize, Serialize};

/// A floor. Below this a context window is not worth having, so a tier that
/// cannot reach it does not fit, whatever the weights say.
const MIN_CTX: u32 = 4096;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Download {
    pub what: String,
    pub repo: String,
    pub file: Option<String>,
    pub bytes: u64,
    pub url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Plan {
    pub tier: u8,
    pub label: String,
    pub model: String,
    pub repo: String,
    pub file: String,
    pub quant: String,
    pub note: String,

    /// False when the brain and the voice cannot both stay resident, so they
    /// take turns. This is the flag the small-machine warning renders from.
    pub coexist: bool,

    pub backend: String,
    pub n_ctx: u32,
    pub n_gpu_layers: i32,
    /// Derived from compute capability. Replaces the hardcoded 89 in the two
    /// CUDA build scripts.
    pub cuda_arch: Option<String>,

    pub downloads: Vec<Download>,
    pub total_download_bytes: u64,
    pub disk_required_bytes: u64,

    pub memory_pool_bytes: u64,
    pub budget_bytes: u64,

    /// Why. Every decision explains itself, because if the plan cannot the
    /// interface has to invent an explanation, and that is how interfaces
    /// start lying to people.
    pub reasons: Vec<String>,
    pub warnings: Vec<String>,
}

#[derive(Debug)]
pub enum PlanError {
    TooSmall {
        pool: u64,
        budget: u64,
        smallest: u64,
    },
    EmptyDictionary,
}

impl std::fmt::Display for PlanError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PlanError::TooSmall { pool, budget, smallest } => write!(
                f,
                "this machine cannot run Hearth. It has {} to work with, which leaves {} after \
                 the voice, speech recognition and headroom, and the smallest model is {}.",
                human(*pool), human(*budget), human(*smallest)
            ),
            PlanError::EmptyDictionary => write!(f, "the dictionary has no tiers"),
        }
    }
}

impl std::error::Error for PlanError {}

pub fn plan(m: &Machine, d: &Dictionary) -> Result<Plan, PlanError> {
    if d.tiers.is_empty() {
        return Err(PlanError::EmptyDictionary);
    }
    let r = &d.reserves;
    let pool = m.memory_pool();

    // Held back before any model is considered. On unified memory the host
    // operating system comes out of the same pool, which is the whole reason an
    // 8 GB Mac is a different problem from an 8 GB graphics card.
    let mut base = r.stt_bytes + r.headroom_bytes;
    if m.unified_memory {
        base += r.os_unified_bytes;
    }

    let coexist_budget = pool.saturating_sub(base + r.voice_resident_bytes);
    let sequential_budget = pool.saturating_sub(base);

    let mut reasons = Vec::new();
    let mut warnings = Vec::new();

    // Take the best that fits with the voice resident. Only if nothing does do
    // we consider making them take turns.
    let (tier, file, quant, bytes, coexist, budget) =
        match best_fit(d, coexist_budget) {
            Some((t, f, q, b)) => {
                reasons.push(format!(
                    "{} of {} is usable after holding back the voice, speech recognition and headroom.",
                    human(coexist_budget), human(pool)
                ));
                (t, f, q, b, true, coexist_budget)
            }
            None => match best_fit(d, sequential_budget) {
                Some((t, f, q, b)) => {
                    reasons.push(format!(
                        "Nothing fits with the voice held in memory, so the mind and the voice \
                         will take turns. That frees {} instead of {}.",
                        human(sequential_budget), human(coexist_budget)
                    ));
                    warnings.push(
                        "Your persona will think and speak one at a time. You will hear a short \
                         pause before a reply is spoken."
                            .into(),
                    );
                    (t, f, q, b, false, sequential_budget)
                }
                None => {
                    return Err(PlanError::TooSmall {
                        pool,
                        budget: sequential_budget,
                        smallest: d.smallest().map(|t| t.bytes).unwrap_or(0),
                    })
                }
            },
        };

    if file != tier.file {
        reasons.push(format!(
            "The preferred {} build did not fit, so this is the smaller {} build of the same model.",
            tier.quant, quant
        ));
    }

    // Context gets whatever the weights left behind.
    let left = budget.saturating_sub(bytes);
    let raw = (left / tier.kv_bytes_per_token) as u32;
    let n_ctx = (raw.min(tier.max_ctx).max(MIN_CTX) / 1024) * 1024;
    reasons.push(format!(
        "{} is left after the weights, which is about {} tokens of context at this model's rate.",
        human(left), n_ctx
    ));

    let backend = m.backend().to_string();
    let n_gpu_layers = if backend == "cpu" { 0 } else { -1 };
    if backend == "cpu" {
        warnings.push(
            "No supported graphics card was found, so this will run on the processor. It will \
             work, and it will be slow enough that a voice conversation is not realistic."
                .into(),
        );
    }

    let cuda_arch = m
        .gpu
        .as_ref()
        .and_then(|g| g.compute_cap.as_ref())
        .map(|c| c.replace('.', ""));
    if let Some(a) = &cuda_arch {
        reasons.push(format!(
            "CUDA builds target architecture {}, read from the card rather than assumed.",
            a
        ));
    }

    let downloads = vec![
        Download {
            what: format!("{} ({})", tier.model, quant),
            repo: tier.repo.clone(),
            file: Some(file.clone()),
            bytes,
            url: Some(hf_url(&tier.repo, &file)),
        },
        Download {
            what: d.voice.name.clone(),
            repo: d.voice.repo.clone(),
            file: None,
            bytes: d.voice.download_bytes,
            url: None,
        },
    ];
    let total: u64 = downloads.iter().map(|x| x.bytes).sum();

    // Room to land the download and to unpack it, plus the runtime itself.
    let disk_required = total + (total / 5);
    if m.free_disk_bytes < disk_required {
        warnings.push(format!(
            "Only {} free on disk and this needs about {}.",
            human(m.free_disk_bytes), human(disk_required)
        ));
    }

    if m.os == "windows" && m.wsl_present == Some(false) {
        warnings.push(
            "The Windows Subsystem for Linux is not installed yet. Hearth will offer to install \
             it, which needs a restart."
                .into(),
        );
    }

    Ok(Plan {
        tier: tier.id,
        label: tier.label.clone(),
        model: tier.model.clone(),
        repo: tier.repo.clone(),
        file,
        quant,
        note: tier.note.trim().to_string(),
        coexist,
        backend,
        n_ctx,
        n_gpu_layers,
        cuda_arch,
        downloads,
        total_download_bytes: total,
        disk_required_bytes: disk_required,
        memory_pool_bytes: pool,
        budget_bytes: budget,
        reasons,
        warnings,
    })
}

/// Largest tier whose weights plus a floor of context fit the budget. Tries the
/// preferred build first, then that tier's smaller fallback.
fn best_fit<'a>(d: &'a Dictionary, budget: u64) -> Option<(&'a Tier, String, String, u64)> {
    for t in d.descending() {
        let floor = t.kv_bytes_per_token * MIN_CTX as u64;
        if t.bytes + floor <= budget {
            return Some((t, t.file.clone(), t.quant.clone(), t.bytes));
        }
        if let Some(fb) = &t.fallback {
            if fb.bytes + floor <= budget {
                return Some((t, fb.file.clone(), fb.quant.clone(), fb.bytes));
            }
        }
    }
    None
}
