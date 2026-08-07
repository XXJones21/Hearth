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

/// One quantisation of a tier's model. A tier is a model; a build is a way of
/// storing it, and the difference between two builds is bits per weight traded
/// for the context window those bytes would otherwise have held.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Build {
    pub file: String,
    pub quant: String,
    pub bytes: u64,
    /// See `Fallback::sha256`. Every build listed here carries one, because a
    /// build the planner can choose is a build the installer will download.
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
    /// The quantisation ladder, best quality first. When a tier lists one the
    /// planner chooses from it; when it does not, the preferred build and its
    /// single fallback are the whole ladder, which is what every tier was
    /// before the catalogue grew.
    #[serde(default)]
    pub builds: Vec<Build>,
}

impl Tier {
    /// Every build of this tier, best quality first. The ladder the planner
    /// walks: the first rung that clears the context target wins, so ordering
    /// here IS the quality judgement and belongs in the dictionary rather than
    /// in a sort the code invents.
    pub fn ladder(&self) -> Vec<Build> {
        if !self.builds.is_empty() {
            return self.builds.clone();
        }
        let mut out = vec![Build {
            file: self.file.clone(),
            quant: self.quant.clone(),
            bytes: self.bytes,
            sha256: self.sha256.clone(),
        }];
        if let Some(fb) = &self.fallback {
            out.push(Build {
                file: fb.file.clone(),
                quant: fb.quant.clone(),
                bytes: fb.bytes,
                sha256: fb.sha256.clone(),
            });
        }
        out
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeArtifact {
    pub url: String,
    pub bytes: u64,
    #[serde(default)]
    pub sha256: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct RuntimePython {
    #[serde(default)]
    pub windows: Option<RuntimeArtifact>,
    #[serde(default)]
    pub macos: Option<RuntimeArtifact>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct RuntimeLlama {
    #[serde(default)]
    pub release: String,
    #[serde(default)]
    pub windows_cuda: Vec<RuntimeArtifact>,
    #[serde(default)]
    pub windows_vulkan: Vec<RuntimeArtifact>,
    #[serde(default)]
    pub macos_metal: Vec<RuntimeArtifact>,
}

/// The voice engine's pip environment.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct RuntimeVoiceEnv {
    #[serde(default)]
    pub package: String,
    #[serde(default)]
    pub extras: Vec<String>,
    #[serde(default)]
    pub torch_index_cuda: Option<String>,
}

/// What the installer places under <root>/runtime, beyond the models.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Runtime {
    #[serde(default)]
    pub python: RuntimePython,
    #[serde(default)]
    pub llama_server: RuntimeLlama,
    #[serde(default)]
    pub voice_env: RuntimeVoiceEnv,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Dictionary {
    #[serde(default)]
    pub runtime: Runtime,
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
