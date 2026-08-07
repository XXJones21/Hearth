//! What this machine should run.
//!
//! PURE. No I/O, no environment, no clock. Same `Machine` plus same
//! `Dictionary` always yields the same `Plan`. That is what makes the budget
//! arithmetic testable against fixtures instead of needing four computers.

use crate::dict::{hf_url, Build, Dictionary, Tier};
use crate::machine::Machine;
use crate::human;
use serde::{Deserialize, Serialize};

/// A floor. Below this a context window is not worth having, so a tier that
/// cannot reach it does not fit, whatever the weights say.
const MIN_CTX: u32 = 4096;

/// What a context window has to reach before the planner stops spending bytes
/// on weights. Context used to be pure residue: take the best quantisation
/// that fits and let the window be whatever survived. On an 8 GB machine that
/// produced 9216 tokens against a persona prompt of 1263, which is a model
/// that cannot hold a conversation it is otherwise good enough to have. So the
/// window is a constraint now, and the quantisation is what gives way.
///
/// Only within a tier. Choosing a smaller MODEL to buy context would mean more
/// memory could yield a worse brain, and that ordering is load-bearing.
const TARGET_CTX: u32 = 16384;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Download {
    pub what: String,
    pub repo: String,
    pub file: Option<String>,
    pub bytes: u64,
    pub url: Option<String>,
    /// Hex sha256 from the dictionary. Verified after the bytes land; a
    /// mismatch is fatal, absence is only noted.
    pub sha256: Option<String>,
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

    // The voice costs what its engine costs, and which engine runs depends on
    // the platform while omnivoice.cpp is still crossing over. A machine on
    // the C++ engine holds ~900 MB where the torch one holds 2.2 GiB, and on
    // 8 GB that difference decides whether the voice can stay resident at all.
    let voice_resident = d.voice.resident_for(&m.os, r.voice_resident_bytes);
    let coexist_budget = pool.saturating_sub(base + voice_resident);
    let sequential_budget = pool.saturating_sub(base);

    let mut reasons = Vec::new();
    let mut warnings = Vec::new();

    // Take the best that fits with the voice resident. Only if nothing does do
    // we consider making them take turns.
    let (tier, build, coexist, budget) =
        match best_fit(d, coexist_budget) {
            Some((t, b)) => {
                reasons.push(format!(
                    "{} of {} is usable after holding back the voice, speech recognition and headroom.",
                    human(coexist_budget), human(pool)
                ));
                (t, b, true, coexist_budget)
            }
            None => match best_fit(d, sequential_budget) {
                Some((t, b)) => {
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
                    (t, b, false, sequential_budget)
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

    let ladder = tier.ladder();
    let preferred = &ladder[0];
    let n_ctx = ctx_for(tier, budget, build.bytes);
    if build.file != preferred.file {
        let floor = tier.kv_bytes_per_token * MIN_CTX as u64;
        if preferred.bytes + floor > budget {
            reasons.push(format!(
                "The preferred {} build did not fit, so this is the smaller {} build of the same model.",
                preferred.quant, build.quant
            ));
        } else {
            // It fit. It was passed over anyway, and saying so is the whole
            // point of a plan that explains itself: someone comparing two
            // machines needs to know this was a choice, not a limit.
            reasons.push(format!(
                "The {} build fits but would leave only {} tokens of context, so this is the {} \
                 build, which holds {} instead.",
                preferred.quant,
                ctx_for(tier, budget, preferred.bytes),
                build.quant,
                n_ctx
            ));
        }
    }

    let left = budget.saturating_sub(build.bytes);
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
            what: format!("{} ({})", tier.model, build.quant),
            repo: tier.repo.clone(),
            file: Some(build.file.clone()),
            bytes: build.bytes,
            url: Some(hf_url(&tier.repo, &build.file)),
            sha256: build.sha256.clone(),
        },
        Download {
            what: d.voice.name.clone(),
            repo: d.voice.repo_for(&m.os).to_string(),
            // The C++ engine names its two weight files; the torch one takes a
            // whole-repository snapshot and has nothing to name.
            file: None,
            bytes: d.voice.download_bytes_for(&m.os),
            url: None,
            sha256: None,
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
        file: build.file.clone(),
        quant: build.quant.clone(),
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

/// The context window a build leaves behind, rounded the way the plan reports
/// it. One definition, used both to choose a build and to report the choice,
/// so the number in the reason is the number the house is configured with.
pub(crate) fn ctx_for(t: &Tier, budget: u64, bytes: u64) -> u32 {
    let left = budget.saturating_sub(bytes);
    let raw = (left / t.kv_bytes_per_token) as u32;
    (raw.min(t.max_ctx).max(MIN_CTX) / 1024) * 1024
}

/// Largest tier whose weights plus a floor of context fit the budget, and
/// within that tier the best build that still clears `TARGET_CTX`.
///
/// Two separate questions, deliberately. Which model is a question about the
/// machine's size and is answered first and alone; which build of that model
/// is a question about how to spend what is left, and cannot reach back and
/// change the answer to the first.
fn best_fit<'a>(d: &'a Dictionary, budget: u64) -> Option<(&'a Tier, Build)> {
    // A tier only counts as fitting if some build of it can hold the target
    // window. Weights that fit with nothing left for context are a model that
    // cannot be talked to: an RTX 4080 reaches the 26B with 4096 tokens, which
    // is a worse machine than the same card running the 12B at 65536. Size is
    // not the only axis, and the largest thing that technically loads is not
    // the best plan.
    if let Some(found) = fit_at(d, budget, TARGET_CTX) {
        return Some(found);
    }
    // Nothing anywhere reaches the target, so take the floor rather than
    // refuse the machine. A small window is still a working Hearth.
    fit_at(d, budget, MIN_CTX)
}

/// Largest tier with a build that holds `want_ctx`, and the best such build.
fn fit_at<'a>(d: &'a Dictionary, budget: u64, want_ctx: u32) -> Option<(&'a Tier, Build)> {
    for t in d.descending() {
        let floor = t.kv_bytes_per_token * MIN_CTX as u64;
        let ladder = t.ladder();
        let fitting: Vec<&Build> = ladder
            .iter()
            .filter(|b| b.bytes + floor <= budget && ctx_for(t, budget, b.bytes) >= want_ctx)
            .collect();
        if let Some(chosen) = fitting.first() {
            return Some((t, (*chosen).clone()));
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::machine;

    fn plan_for(fixture: &str) -> Result<Plan, PlanError> {
        let m = machine::simulated(fixture).expect("fixture exists");
        let d = Dictionary::embedded().expect("embedded dictionary parses");
        plan(&m, &d)
    }

    // The 8 GB Air, after the measured reserves and the cpp voice: it keeps
    // its preferred quant, holds the voice resident, and clears TARGET_CTX.
    // These numbers are the merge's own claim (0a730f5) pinned as a contract.
    #[test]
    fn air_8gb_keeps_its_quant_and_its_voice() {
        let p = plan_for("m1-air-8gb").unwrap();
        assert_eq!(p.tier, 0);
        assert_eq!(p.quant, "Q4_K_M");
        assert!(p.coexist, "the cpp voice fits alongside on 8 GB");
        assert!(p.n_ctx >= TARGET_CTX, "a usable window is a constraint now");
    }

    #[test]
    fn rtx4080_takes_the_12b_at_full_context() {
        let p = plan_for("rtx4080").unwrap();
        assert_eq!(p.tier, 2);
        assert!(p.coexist);
        assert_eq!(p.n_ctx, 65536);
    }

    #[test]
    fn rtx4080_does_not_reach_the_26b() {
        let p = plan_for("rtx4080").unwrap();
        assert!(p.tier < 3);
    }

    #[test]
    fn a_machine_below_the_floor_is_refused_clearly() {
        let err = plan_for("tiny").unwrap_err();
        let text = err.to_string();
        assert!(text.contains("cannot run Hearth"));
    }

    #[test]
    fn no_gpu_falls_to_cpu_with_a_warning() {
        let p = plan_for("no-gpu").unwrap();
        assert_eq!(p.backend, "cpu");
        assert!(p.warnings.iter().any(|w| w.contains("processor")));
    }

    #[test]
    fn every_plan_explains_itself() {
        for fixture in ["rtx4080", "m1-air-8gb", "m1-air-16gb", "no-gpu"] {
            let p = plan_for(fixture).unwrap();
            assert!(!p.reasons.is_empty(), "{fixture} must carry reasons");
        }
    }
}
