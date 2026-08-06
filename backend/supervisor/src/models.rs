//! Model identifiers, resolved to files on this machine.
//!
//! The supervisor's half of the same join the harness does in
//! `valar/models.py`: a persona names a model id, the dictionary at
//! `crates/hearth-probe/dictionary.yaml` records the filename for it, and
//! HEARTH_MODELS says where files live. Two implementations because the
//! harness and the supervisor are separate processes in different languages
//! and both have to turn a persona into a path.
//!
//! The dictionary is read with a small line scanner rather than a YAML crate.
//! Two fields out of one nested list is not worth a dependency, and the
//! supervisor's lockfile is vendored, so adding one would mean a fetch at
//! build time that the image build is designed to avoid.

use std::env;
use std::path::PathBuf;

/// Dictionary tiers are numbered; persona manifests name them. The same table
/// lives in valar/models.py and scripts/render_config.py.
const TIER_IDS: [(u8, &str); 4] = [
    (0, "gemma-4-e2b"),
    (1, "gemma-4-e4b"),
    (2, "gemma-4-12b-qat"),
    (3, "gemma-4-26b-a4b"),
];

fn tier_for(model_id: &str) -> Option<u8> {
    TIER_IDS
        .iter()
        .find(|(_, name)| name.eq_ignore_ascii_case(model_id))
        .map(|(tier, _)| *tier)
}

fn dictionary_candidates(repo_root: &std::path::Path) -> Vec<PathBuf> {
    if let Ok(configured) = env::var("HEARTH_DICTIONARY") {
        if !configured.trim().is_empty() {
            return vec![PathBuf::from(configured.trim())];
        }
    }
    let mut candidates = vec![repo_root.join("dictionary.yaml")];
    if let Some(parent) = repo_root.parent() {
        candidates.push(
            parent
                .join("crates")
                .join("hearth-probe")
                .join("dictionary.yaml"),
        );
    }
    candidates
}

/// The GGUF filename the dictionary records for a tier.
///
/// Scans the `tiers:` list for the entry whose `id:` matches, then returns its
/// `file:`. Both keys are two-space-indented scalars under a list item, which
/// is the shape the dictionary has and the shape its own comments describe.
fn filename_for_tier(body: &str, tier: u8) -> Option<String> {
    let mut in_tiers = false;
    let mut current_tier: Option<u8> = None;
    let mut current_file: Option<String> = None;

    for line in body.lines() {
        let trimmed = line.trim_start();
        if !line.starts_with(' ') && !line.starts_with('-') {
            in_tiers = line.starts_with("tiers:");
            continue;
        }
        if !in_tiers {
            continue;
        }
        // A new list item ends the previous entry.
        if trimmed.starts_with("- ") {
            if current_tier == Some(tier) {
                if let Some(file) = current_file.take() {
                    return Some(file);
                }
            }
            current_tier = None;
            current_file = None;
        }
        let item = trimmed.trim_start_matches("- ").trim();
        if let Some(value) = item.strip_prefix("id:") {
            current_tier = value.trim().parse::<u8>().ok();
        } else if let Some(value) = item.strip_prefix("file:") {
            // Only the tier's own file, never the nested fallback's, which is
            // indented deeper under `fallback:`.
            if current_file.is_none() && indent_of(line) <= 4 {
                current_file = Some(value.trim().to_string());
            }
        }
    }
    if current_tier == Some(tier) {
        return current_file;
    }
    None
}

fn indent_of(line: &str) -> usize {
    line.len() - line.trim_start().len()
}

/// A persona's model id to an absolute path, or None when it cannot be resolved.
pub fn resolve(repo_root: &std::path::Path, model_id: &str) -> Option<PathBuf> {
    let tier = tier_for(model_id)?;
    let body = dictionary_candidates(repo_root)
        .into_iter()
        .find_map(|path| std::fs::read_to_string(path).ok())?;
    let file = filename_for_tier(&body, tier)?;
    Some(models_dir().join(file))
}

/// Where weights live. Outside the product tree, on the native filesystem: the
/// same file on a mounted Windows filesystem takes minutes to load rather than
/// seconds, and that can exceed the model swap timeout.
pub fn models_dir() -> PathBuf {
    if let Ok(configured) = env::var("HEARTH_MODELS") {
        if !configured.trim().is_empty() {
            return crate::config::normalize_path(configured.trim());
        }
    }
    let home = env::var("HEARTH_HOME")
        .ok()
        .filter(|v| !v.trim().is_empty())
        .map(|v| crate::config::normalize_path(v.trim()))
        .or_else(|| env::var("HOME").ok().map(|h| PathBuf::from(h).join(".hearth")))
        .unwrap_or_else(|| PathBuf::from(".hearth"));
    home.join("models")
}

#[cfg(test)]
mod tests {
    use super::*;

    const DICT: &str = "\
tiers:
  - id: 1
    file: gemma-4-E4B-it-Q4_K_M.gguf
    fallback:
      file: gemma-4-E4B-it-Q3_K_M.gguf
  - id: 2
    file: gemma-4-12B-it-qat-UD-Q4_K_XL.gguf
    fallback: null
";

    #[test]
    fn reads_the_tier_file_and_not_the_fallback() {
        assert_eq!(
            filename_for_tier(DICT, 1).as_deref(),
            Some("gemma-4-E4B-it-Q4_K_M.gguf")
        );
        assert_eq!(
            filename_for_tier(DICT, 2).as_deref(),
            Some("gemma-4-12B-it-qat-UD-Q4_K_XL.gguf")
        );
        assert_eq!(filename_for_tier(DICT, 3), None);
    }

    #[test]
    fn ids_map_to_tiers() {
        assert_eq!(tier_for("gemma-4-12b-qat"), Some(2));
        assert_eq!(tier_for("nothing"), None);
    }
}
