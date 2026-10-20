//! Build a snapshot from GitHub with `gh api`, one call per policy issue.
//!
//! `gh` is run as a subprocess so the same code works with the workflow's
//! `GITHUB_TOKEN` (via `GH_TOKEN`) and with a developer's `gh auth login`.
//! Set `ALLEN_GUARD_GH` to use a different `gh` binary (tests do).

use crate::close::Issue;
use crate::policy::Policy;
use serde::Deserialize;
use std::process::Command;

#[derive(Deserialize)]
struct ApiIssue {
    state: String,
    #[serde(default)]
    state_reason: Option<String>,
    #[serde(default)]
    title: String,
    #[serde(default)]
    body: Option<String>,
    #[serde(default)]
    labels: Vec<ApiLabel>,
    #[serde(default)]
    html_url: Option<String>,
}

#[derive(Deserialize)]
struct ApiLabel {
    name: String,
}

/// Fetch one issue. The snapshot keys it by the policy's `repo`/`number`
/// even if GitHub redirected a transferred issue; `html_url` records where
/// it actually lives.
pub fn fetch_issue(repo: &str, number: u64) -> Result<Issue, String> {
    let gh = std::env::var("ALLEN_GUARD_GH").unwrap_or_else(|_| "gh".into());
    let endpoint = format!("repos/{repo}/issues/{number}");
    let out = Command::new(&gh)
        .args(["api", &endpoint])
        .output()
        .map_err(|e| format!("{repo}#{number}: cannot run {gh}: {e}"))?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        let first = err.lines().next().unwrap_or("").trim();
        return Err(format!(
            "{repo}#{number}: gh api failed ({}): {first}",
            out.status
        ));
    }
    let api: ApiIssue = serde_json::from_slice(&out.stdout)
        .map_err(|e| format!("{repo}#{number}: unexpected gh api output: {e}"))?;
    Ok(Issue {
        repo: repo.to_string(),
        number,
        state: api.state,
        state_reason: api.state_reason,
        title: api.title,
        body: api.body,
        labels: api.labels.into_iter().map(|l| l.name).collect(),
        html_url: api.html_url,
    })
}

/// Fetch every issue the policy names. Failures are returned, not hidden;
/// the failed issues are absent from the snapshot and so evaluate as
/// "not fetched" blockers.
pub fn build_snapshot<F>(policy: &Policy, mut fetch: F) -> (Vec<Issue>, Vec<String>)
where
    F: FnMut(&str, u64) -> Result<Issue, String>,
{
    let mut issues = Vec::new();
    let mut errors = Vec::new();
    for r in policy.required() {
        match fetch(&r.repo, r.number) {
            Ok(i) => issues.push(i),
            Err(e) => errors.push(e),
        }
    }
    (issues, errors)
}
