//! The budget arithmetic, against machines with known-correct answers.
//!
//! These run without hardware, which is the entire reason `plan` is pure.

use hearth_probe::{machine, plan, Dictionary};

fn d() -> Dictionary {
    Dictionary::embedded().expect("embedded dictionary parses")
}

fn m(name: &str) -> machine::Machine {
    machine::simulated(name).unwrap_or_else(|| panic!("fixture {name}"))
}

#[test]
fn rtx4080_takes_the_12b_with_the_voice_resident() {
    let p = plan(&m("rtx4080"), &d()).expect("a 4080 can run Hearth");
    assert_eq!(p.tier, 2, "16 GB should land on the 12B QAT");
    assert_eq!(p.repo, "unsloth/gemma-4-12B-it-qat-GGUF");
    assert_eq!(p.file, "gemma-4-12B-it-qat-UD-Q4_K_XL.gguf");
    assert!(p.coexist, "16 GB holds the mind and the voice together");
    assert_eq!(p.backend, "cuda");
    assert_eq!(p.cuda_arch.as_deref(), Some("89"));
    assert_eq!(p.n_gpu_layers, -1);
}

#[test]
fn rtx4080_does_not_reach_the_26b() {
    // 12.73 GB of weights does not fit an 11.8 GB budget. If this starts
    // passing, a reservation shrank and the arithmetic needs re-reading.
    let p = plan(&m("rtx4080"), &d()).unwrap();
    assert_ne!(p.tier, 3);
}

#[test]
fn m1_air_8gb_holds_the_mind_and_the_voice_together() {
    // This used to assert the opposite. The 8 GB Air could not hold both while
    // the voice was the torch build at 2.2 GiB, and the honest interim was a
    // written first meeting. omnivoice.cpp holds ~900 MB, which is the whole
    // difference: the machine coexists, and the take-turns orchestration that
    // `coexist: false` promised may never need building for this class.
    let p = plan(&m("m1-air-8gb"), &d()).expect("an 8 GB Air can run Hearth");
    assert_eq!(p.tier, 0, "8 GB unified is a tier 0 machine");
    assert_eq!(p.repo, "unsloth/gemma-4-E2B-it-GGUF");
    assert!(p.coexist, "8 GB holds both once the voice is the C++ engine");
    assert_eq!(p.backend, "metal");
    assert!(p.cuda_arch.is_none(), "no CUDA on Apple Silicon");
    assert!(
        !p.warnings.iter().any(|w| w.contains("one at a time")),
        "nothing takes turns any more, so nobody should be warned that it does"
    );
}

#[test]
fn no_machine_is_given_weights_it_cannot_talk_to() {
    // The rule the RTX 4080 taught us: it reached the 26B and sat at the 4096
    // floor, which is a worse machine than the same card running the 12B at
    // 65536. A tier only fits if some build of it can hold the target window,
    // so "largest model that technically loads" is not the plan.
    //
    // NOTE: no fixture currently exercises the within-tier trade-down, because
    // with the measured reserves every one of them affords its preferred
    // build. The ladder still matters for machines between these sizes; if a
    // fixture is ever added that trades down, assert the "fits but would
    // leave" reason here too.
    for name in ["rtx4080", "m1-air-8gb", "m1-air-16gb", "no-gpu"] {
        let p = plan(&m(name), &d()).unwrap();
        assert!(
            p.n_ctx >= 16384,
            "{name} planned {} tokens, below the target; a bigger model was taken \
             in place of a usable window",
            p.n_ctx
        );
    }
}

#[test]
fn a_machine_with_room_keeps_its_preferred_build() {
    // The target must not cost quality where quality was affordable.
    let p = plan(&m("rtx4080"), &d()).unwrap();
    assert_eq!(p.quant, "UD-Q4_K_XL", "a 4080 has room for the best build");
    assert!(p.n_ctx >= 16384);
}

#[test]
fn every_selectable_build_can_be_verified() {
    // A build the planner may choose is a build the installer will download,
    // and a download with no hash is one nothing checks.
    for t in &d().tiers {
        for b in &t.builds {
            assert!(
                b.sha256.as_ref().is_some_and(|s| s.len() == 64),
                "tier {} build {} has no usable sha256",
                t.id,
                b.quant
            );
            assert!(b.bytes > 0, "tier {} build {} has no size", t.id, b.quant);
        }
    }
}

#[test]
fn m1_air_16gb_does_better_than_the_8gb() {
    let small = plan(&m("m1-air-8gb"), &d()).unwrap();
    let big = plan(&m("m1-air-16gb"), &d()).unwrap();
    assert!(big.tier >= small.tier, "more memory must never mean a smaller model");
    assert!(big.coexist, "16 GB unified should hold both");
}

#[test]
fn no_gpu_still_produces_a_plan() {
    let p = plan(&m("no-gpu"), &d()).expect("a CPU machine gets a plan, not a panic");
    assert_eq!(p.backend, "cpu");
    assert_eq!(p.n_gpu_layers, 0);
    assert!(p.warnings.iter().any(|w| w.contains("processor")));
}

#[test]
fn a_machine_below_the_floor_is_refused_clearly() {
    let e = plan(&m("tiny"), &d()).expect_err("4 GB and no GPU is not a Hearth machine");
    let msg = e.to_string();
    assert!(msg.contains("cannot run Hearth"), "got: {msg}");
    assert!(msg.contains("smallest model is"), "the refusal must say why: {msg}");
}

#[test]
fn every_plan_explains_itself() {
    for name in ["rtx4080", "m1-air-8gb", "m1-air-16gb", "no-gpu"] {
        let p = plan(&m(name), &d()).unwrap();
        assert!(!p.reasons.is_empty(), "{name} produced no reasons");
        assert!(!p.note.is_empty(), "{name} produced no note");
        assert!(p.n_ctx >= 4096, "{name} got an unusable context: {}", p.n_ctx);
        assert!(p.total_download_bytes > 0, "{name} downloads nothing");
    }
}

#[test]
fn the_dictionary_is_internally_consistent() {
    let d = d();
    assert!(!d.tiers.is_empty());
    for t in &d.tiers {
        assert!(t.bytes > 0, "tier {} has no size", t.id);
        assert!(t.file.ends_with(".gguf"), "tier {} file is not a gguf", t.id);
        assert!(t.repo.contains('/'), "tier {} repo is not owner/name", t.id);
        assert!(t.kv_bytes_per_token > 0, "tier {} has no kv rate", t.id);
        if let Some(f) = &t.fallback {
            assert!(
                f.bytes < t.bytes || t.id == 3,
                "tier {} fallback is not smaller than its preferred build",
                t.id
            );
        }
    }
}
