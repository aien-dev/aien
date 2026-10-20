//! Programme close guard: pure evaluation of a snapshot against the policy.
//!
//! An issue is *accepted* when it is closed with `state_reason` `completed`,
//! its body has no unchecked task-list item (`- [ ]`), and no status line of
//! its body carries a forbidden marker. A prerequisite (never a phase, never
//! the programme) carrying a waiver label skips the two body checks; it must
//! still be closed as completed, and the waiver is reported.
//!
//! The programme issue itself is not required to be closed (its closure is
//! what triggers the guard), but its own body checklist must be complete.
//! An issue the policy names but the snapshot lacks is a blocker
//! ("not fetched"), never silently accepted.

use crate::policy::{key, Policy, Role};
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::LazyLock;

/// One issue as recorded in a snapshot.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Issue {
    pub repo: String,
    pub number: u64,
    /// "open" or "closed".
    pub state: String,
    #[serde(default)]
    pub state_reason: Option<String>,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub body: Option<String>,
    #[serde(default)]
    pub labels: Vec<String>,
    /// Where the issue actually lives (differs after a transfer). Optional.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub html_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct Blocker {
    pub repo: String,
    pub number: u64,
    pub role: Role,
    pub label: String,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct WaiverNote {
    pub repo: String,
    pub number: u64,
    pub label: String,
    /// The waiver label found on the issue.
    pub waiver: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct Verdict {
    pub accepted: bool,
    pub programme: String,
    /// State of the programme issue in the snapshot ("open", "closed" or
    /// "not fetched").
    pub programme_state: String,
    pub required: usize,
    pub blockers: Vec<Blocker>,
    /// Waivers honoured (prerequisites only).
    pub waived: Vec<WaiverNote>,
    /// Waiver labels found on phases or the programme and ignored.
    pub ignored_waivers: Vec<WaiverNote>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub fetch_errors: Vec<String>,
}

static UNCHECKED: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?m)^[ \t>]*(?:[-*+]|\d+[.)])[ \t]+\[ \]").unwrap());

/// Number of unchecked task-list items anywhere in `body`.
pub fn unchecked_items(body: &str) -> usize {
    UNCHECKED.find_iter(body).count()
}

/// Forbidden markers present on status lines of `body`, in policy order.
pub fn forbidden_markers(body: &str, policy: &Policy) -> Vec<String> {
    let keywords: Vec<String> = policy
        .acceptance
        .status_keywords
        .iter()
        .map(|k| k.to_lowercase())
        .collect();
    let status_lines: Vec<String> = body
        .lines()
        .map(str::to_lowercase)
        .filter(|l| keywords.iter().any(|k| l.contains(k.as_str())))
        .collect();
    policy
        .acceptance
        .forbid_markers
        .iter()
        .filter(|m| {
            let m = m.to_lowercase();
            status_lines.iter().any(|l| l.contains(m.as_str()))
        })
        .cloned()
        .collect()
}

/// Evaluate `snapshot` against `policy`.
pub fn evaluate(policy: &Policy, snapshot: &[Issue]) -> Verdict {
    let by_key: HashMap<(String, u64), &Issue> = snapshot
        .iter()
        .map(|i| (key(&i.repo, i.number), i))
        .collect();
    let required = policy.required();
    let mut blockers = Vec::new();
    let mut waived = Vec::new();
    let mut ignored_waivers = Vec::new();
    let mut programme_state = "not fetched".to_string();

    for r in &required {
        let block = |reason: String| Blocker {
            repo: r.repo.clone(),
            number: r.number,
            role: r.role,
            label: r.label.clone(),
            reason,
        };
        let Some(issue) = by_key.get(&key(&r.repo, r.number)) else {
            blockers.push(block("not fetched".into()));
            continue;
        };
        if r.role == Role::Programme {
            programme_state = issue.state.clone();
        }

        let waiver = issue
            .labels
            .iter()
            .find(|l| policy.acceptance.waiver_labels.iter().any(|w| w == *l));
        let mut body_waived = false;
        if let Some(w) = waiver {
            let note = WaiverNote {
                repo: r.repo.clone(),
                number: r.number,
                label: r.label.clone(),
                waiver: w.clone(),
            };
            if r.role == Role::Prerequisite {
                body_waived = true;
                waived.push(note);
            } else {
                ignored_waivers.push(note);
            }
        }

        if r.role != Role::Programme {
            if let Some(reason) = state_problem(issue) {
                blockers.push(block(reason));
            }
        }
        if !body_waived {
            for reason in body_problems(issue, policy) {
                blockers.push(block(reason));
            }
        }
    }

    Verdict {
        accepted: blockers.is_empty(),
        programme: format!("{}#{}", policy.programme.repo, policy.programme.number),
        programme_state,
        required: required.len(),
        blockers,
        waived,
        ignored_waivers,
        fetch_errors: Vec::new(),
    }
}

fn state_problem(issue: &Issue) -> Option<String> {
    match issue.state.as_str() {
        "open" => Some("open".into()),
        "closed" => match issue.state_reason.as_deref() {
            Some("completed") => None,
            Some(other) => Some(format!("closed as {other}, not completed")),
            None => Some("closed without state_reason completed".into()),
        },
        other => Some(format!("unknown state {other:?}")),
    }
}

fn body_problems(issue: &Issue, policy: &Policy) -> Vec<String> {
    let body = issue.body.as_deref().unwrap_or("");
    let mut out = Vec::new();
    let n = unchecked_items(body);
    if n > 0 {
        out.push(format!("{n} unchecked task-list item(s)"));
    }
    for m in forbidden_markers(body, policy) {
        out.push(format!("status line carries forbidden marker `{m}`"));
    }
    out
}

/// Markdown body for the guard's issue comment. Carries no issue text, only
/// references, reasons and policy markers.
pub fn render_markdown(v: &Verdict, policy: &Policy) -> String {
    let mut s = String::new();
    if v.accepted {
        s.push_str("## Programme close guard: accepted\n\n");
        s.push_str(&format!(
            "All {} required issues (programme, {} phases, {} prerequisites) meet the acceptance predicate in `guard/policy.toml`.\n",
            v.required,
            policy.phases.len(),
            v.required - 1 - policy.phases.len()
        ));
        s.push_str("Machine acceptance is necessary, not sufficient: the manual items in `docs/CLOSE_CHECKLIST.md` must also be signed.\n");
    } else {
        s.push_str("## Programme close guard: not accepted\n\n");
        s.push_str(&format!(
            "The programme ({}) cannot be closed: {} blocker(s) across {} required issues. Policy: `guard/policy.toml`.\n\n",
            v.programme,
            v.blockers.len(),
            v.required
        ));
        s.push_str("| Issue | Role | Phase or area | Reason |\n|---|---|---|---|\n");
        for b in &v.blockers {
            s.push_str(&format!(
                "| {}#{} | {} | {} | {} |\n",
                b.repo,
                b.number,
                role_word(b.role),
                b.label,
                b.reason
            ));
        }
    }
    if !v.waived.is_empty() {
        s.push_str("\n**Waivers honoured (prerequisites only, body checks skipped, still must be closed as completed):**\n\n");
        for w in &v.waived {
            s.push_str(&format!(
                "- {}#{} ({}): label `{}`\n",
                w.repo, w.number, w.label, w.waiver
            ));
        }
    }
    if !v.ignored_waivers.is_empty() {
        s.push_str("\n**Waiver labels ignored (phases and the programme cannot be waived):**\n\n");
        for w in &v.ignored_waivers {
            s.push_str(&format!(
                "- {}#{} ({}): label `{}`\n",
                w.repo, w.number, w.label, w.waiver
            ));
        }
    }
    if !v.fetch_errors.is_empty() {
        s.push_str(&format!(
            "\n**{} issue(s) could not be fetched**; they count as blockers until the guard can read them.\n",
            v.fetch_errors.len()
        ));
    }
    s.push_str("\nAn administrator can bypass or remove this automation. Any override is recorded in the audit trail (this comment and the override table in `docs/CLOSE_CHECKLIST.md`) and never counts as passing.\n");
    s
}

fn role_word(r: Role) -> &'static str {
    match r {
        Role::Programme => "programme",
        Role::Phase => "phase",
        Role::Prerequisite => "prerequisite",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unchecked_counts_list_markers_only() {
        let body = "- [ ] a\n- [x] b\n  * [ ] nested\n1. [ ] numbered\n> - [ ] quoted\ntext - [ ] inline\n- [X] done\n";
        assert_eq!(unchecked_items(body), 4);
    }

    #[test]
    fn markers_only_on_status_lines() {
        let policy = Policy::from_toml(
            "[programme]\nrepo='o/r'\nnumber=1\n[[phases]]\nname='P0'\nrepo='o/r'\nnumber=2\n",
        )
        .unwrap();
        let body = "We never accept qualification: NOT_RUN results.\nStatus: PROPOSED; qualification: NOT_RUN.\n";
        // Line 1 is a status line too (it contains "qualification:"), so both match.
        assert_eq!(forbidden_markers(body, &policy).len(), 2);
        let body =
            "Status: COMPLETE; qualification: PASS.\nNotes about Status: PROPOSED-like words";
        assert_eq!(
            forbidden_markers(body, &policy),
            vec!["Status: PROPOSED".to_string()]
        );
        assert!(forbidden_markers("Status: COMPLETE; qualification: PASS.", &policy).is_empty());
    }
}
