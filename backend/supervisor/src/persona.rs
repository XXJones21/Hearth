use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::Serialize;
use serde_json::Value;

#[derive(Debug, Clone, Serialize)]
pub struct PersonaMetadata {
    pub name: String,
    pub description: String,
    pub version: String,
    pub visualization_type: String,
    pub config_url: String,
}

#[derive(Debug, Clone)]
pub struct PersonaStore {
    repo_root: PathBuf,
    asset_base_url: String,
}

impl PersonaStore {
    pub fn new(repo_root: PathBuf, asset_host: &str, asset_port: u16) -> Self {
        let public_host = if asset_host == "0.0.0.0" {
            "127.0.0.1"
        } else {
            asset_host
        };
        Self {
            repo_root,
            asset_base_url: format!("http://{}:{}", public_host, asset_port),
        }
    }

    pub fn list(&self) -> Result<Vec<PersonaMetadata>> {
        let persona_dir = self.repo_root.join("Persona");
        let mut personas = Vec::new();
        for entry in fs::read_dir(&persona_dir)
            .with_context(|| format!("read persona dir {}", persona_dir.display()))?
        {
            let entry = entry?;
            if !entry.file_type()?.is_dir() {
                continue;
            }
            let dir = entry.path();
            if let Ok(config) = self.load_from_dir(&dir) {
                let name = config
                    .get("name")
                    .and_then(Value::as_str)
                    .unwrap_or_else(|| {
                        dir.file_name()
                            .and_then(|s| s.to_str())
                            .unwrap_or("Unknown")
                    })
                    .to_string();
                let description = config
                    .get("description")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_string();
                let version = config
                    .get("version")
                    .and_then(Value::as_str)
                    .unwrap_or("1.0.0")
                    .to_string();
                let visualization_type = config
                    .get("visualization")
                    .and_then(|v| v.get("type"))
                    .and_then(Value::as_str)
                    .unwrap_or("unknown")
                    .to_string();
                let config_file = config_file_name(&dir, &name)
                    .unwrap_or_else(|| format!("{}.json", name.to_ascii_lowercase()));
                personas.push(PersonaMetadata {
                    name: name.clone(),
                    description,
                    version,
                    visualization_type,
                    config_url: format!("{}/Persona/{}/{}", self.asset_base_url, name, config_file),
                });
            }
        }
        personas.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(personas)
    }

    pub fn get(&self, persona_name: &str) -> Result<Value> {
        let dir = self.repo_root.join("Persona").join(persona_name);
        self.load_from_dir(&dir)
    }

    fn load_from_dir(&self, dir: &Path) -> Result<Value> {
        let name = dir
            .file_name()
            .and_then(|s| s.to_str())
            .context("persona directory has no valid name")?;
        let candidates = [
            dir.join(format!("{}.json", name.to_ascii_lowercase())),
            dir.join(format!("{}.json", name)),
        ];
        for candidate in candidates {
            if candidate.exists() {
                let raw = fs::read_to_string(&candidate)
                    .with_context(|| format!("read persona {}", candidate.display()))?;
                return serde_json::from_str(&raw)
                    .with_context(|| format!("parse persona {}", candidate.display()));
            }
        }
        anyhow::bail!("persona config not found in {}", dir.display())
    }
}

fn config_file_name(dir: &Path, name: &str) -> Option<String> {
    let candidates = [
        format!("{}.json", name.to_ascii_lowercase()),
        format!("{}.json", name),
    ];
    candidates
        .into_iter()
        .find(|candidate| dir.join(candidate).exists())
}
