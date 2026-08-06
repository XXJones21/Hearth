//! The model dictionary.
//!
//! Embedded in the binary so it cannot drift from the code that reads it, with
//! an override path so a bench run can try a different tier table without a
//! rebuild.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::Path;

const EMBEDDED: &str = include_str!("../dictionary.yaml");

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Reserves {
    pub voice_resident_bytes: u64,
    pub stt_bytes: u64,
    pub os_unified_bytes: u64,
    pub headroom_bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Voice {
    pub name: String,
    pub repo: String,
    pub download_bytes: u64,
    pub resident_bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Fallback {
    pub file: String,
    pub quant: String,
    pub bytes: u64,
    /// Hex sha256 of the file, from the Hugging Face LFS record. Optional so a
    /// hand-edited dictionary still parses; a download with no hash is noted,
    /// a download with a wrong hash is refused.
    #[serde(default)]
    pub sha256: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tier {
    pub id: u8,
    pub label: String,
    pub model: String,
    pub repo: String,
    pub file: String,
    pub quant: String,
    pub bytes: u64,
    pub max_ctx: u32,
    /// Estimate. The least trustworthy number in the dictionary; err high,
    /// because erring low costs a failed model load.
    pub kv_bytes_per_token: u64,
    pub note: String,
    /// Hex sha256 of the preferred file. See `Fallback::sha256`.
    #[serde(default)]
    pub sha256: Option<String>,
    #[serde(default)]
    pub fallback: Option<Fallback>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Dictionary {
    pub reserves: Reserves,
    pub voice: Voice,
    pub tiers: Vec<Tier>,
}

impl Dictionary {
    pub fn embedded() -> Result<Self> {
        serde_yaml::from_str(EMBEDDED).context("parse embedded dictionary")
    }

    pub fn load(path: &Path) -> Result<Self> {
        let text = std::fs::read_to_string(path)
            .with_context(|| format!("read dictionary {}", path.display()))?;
        serde_yaml::from_str(&text).context("parse dictionary")
    }

    pub fn or_embedded(path: Option<&Path>) -> Result<Self> {
        match path {
            Some(p) => Self::load(p),
            None => Self::embedded(),
        }
    }

    /// Tiers largest first, so the planner takes the best that fits.
    pub fn descending(&self) -> Vec<&Tier> {
        let mut t: Vec<&Tier> = self.tiers.iter().collect();
        t.sort_by(|a, b| b.bytes.cmp(&a.bytes));
        t
    }

    pub fn smallest(&self) -> Option<&Tier> {
        self.tiers.iter().min_by_key(|t| t.bytes)
    }
}

/// Where a file actually comes from.
pub fn hf_url(repo: &str, file: &str) -> String {
    format!("https://huggingface.co/{}/resolve/main/{}", repo, file)
}
