//! The close-guard policy (`guard/policy.toml`).

use serde::Deserialize;
use std::collections::HashSet;
use std::path::Path;

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Policy {
    pub programme: IssueRef,
    pub phases: Vec<Phase>,
    #[serde(default)]
    pub prerequisites: Vec<PrerequisiteGroup>,
    #[serde(default)]
    pub acceptance: Acceptance,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct IssueRef {
    pub repo: String,
    pub number: u64,
    #[serde(default)]
    pub title: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Phase {
    pub name: String,
    pub repo: String,
    pub number: u64,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PrerequisiteGroup {
    pub area: String,
    pub repo: String,
    pub numbers: Vec<u64>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields, default)]
pub struct Acceptance {
    pub status_keywords: Vec<String>,
    pub forbid_markers: Vec<String>,
    pub waiver_labels: Vec<String>,
}

impl Default for Acceptance {
    fn default() -> Self {
        Acceptance {
            status_keywords: vec!["status:".into(), "qualification:".into()],
            forbid_markers: vec!["qualification: NOT_RUN".into(), "Status: PROPOSED".into()],
            waiver_labels: vec!["allen-guard:waived".into()],
        }
    }
}

/// What an issue is to the programme.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    Programme,
    Phase,
    Prerequisite,
}

/// One issue the policy requires, in evaluation order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Required {
    pub role: Role,
    /// "programme", the phase name ("P0") or the prerequisite area.
    pub label: String,
    pub repo: String,
    pub number: u64,
}

impl Policy {
    pub fn from_toml(text: &str) -> Result<Policy, String> {
        let policy: Policy = toml::from_str(text).map_err(|e| format!("policy: {e}"))?;
        policy.validate()?;
        Ok(policy)
    }

    pub fn load(path: &Path) -> Result<Policy, String> {
        let text =
            std::fs::read_to_string(path).map_err(|e| format!("policy {}: {e}", path.display()))?;
        Policy::from_toml(&text)
    }

    fn validate(&self) -> Result<(), String> {
        if self.phases.is_empty() {
            return Err("policy: no phases".into());
        }
        let mut seen = HashSet::new();
        for r in self.required() {
            if !r.repo.contains('/') {
                return Err(format!("policy: repo {:?} is not owner/name", r.repo));
            }
            if !seen.insert(key(&r.repo, r.number)) {
                return Err(format!("policy: {}#{} listed twice", r.repo, r.number));
            }
        }
        Ok(())
    }

    /// Programme first, then phases, then prerequisites, in file order.
    pub fn required(&self) -> Vec<Required> {
        let mut out = vec![Required {
            role: Role::Programme,
            label: "programme".into(),
            repo: self.programme.repo.clone(),
            number: self.programme.number,
        }];
        out.extend(self.phases.iter().map(|p| Required {
            role: Role::Phase,
            label: p.name.clone(),
            repo: p.repo.clone(),
            number: p.number,
        }));
        for g in &self.prerequisites {
            out.extend(g.numbers.iter().map(|&n| Required {
                role: Role::Prerequisite,
                label: g.area.clone(),
                repo: g.repo.clone(),
                number: n,
            }));
        }
        out
    }

    pub fn is_programme(&self, repo: &str, number: u64) -> bool {
        key(repo, number) == key(&self.programme.repo, self.programme.number)
    }
}

/// Case-insensitive identity of an issue.
pub fn key(repo: &str, number: u64) -> (String, u64) {
    (repo.to_ascii_lowercase(), number)
}
