//! Close-guard evaluation on the synthetic snapshots in tests/fixtures/close.

use allen_guard::close::{evaluate, render_markdown, Issue, Verdict};
use allen_guard::policy::{Policy, Role};
use std::path::PathBuf;

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn policy() -> Policy {
    Policy::load(&root().join("policy.toml")).unwrap()
}

fn snapshot(name: &str) -> Vec<Issue> {
    let path = root()
        .join("tests/fixtures/close")
        .join(format!("{name}.json"));
    serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
}

fn blockers(v: &Verdict) -> Vec<(String, u64, String)> {
    v.blockers
        .iter()
        .map(|b| (b.repo.clone(), b.number, b.reason.clone()))
        .collect()
}

fn b(repo: &str, number: u64, reason: &str) -> (String, u64, String) {
    (format!("aien-dev/{repo}"), number, reason.to_string())
}

const UNCHECKED_1: &str = "1 unchecked task-list item(s)";
const NOT_RUN: &str = "status line carries forbidden marker `qualification: NOT_RUN`";
const PROPOSED: &str = "status line carries forbidden marker `Status: PROPOSED`";

#[test]
fn policy_names_programme_eight_phases_and_twenty_one_prerequisites() {
    let p = policy();
    let req = p.required();
    assert_eq!(req.len(), 30);
    assert_eq!(req.iter().filter(|r| r.role == Role::Phase).count(), 8);
    assert_eq!(
        req.iter().filter(|r| r.role == Role::Prerequisite).count(),
        21
    );
}

#[test]
fn all_open_blocks_every_issue_with_exact_reasons() {
    let p = policy();
    let v = evaluate(&p, &snapshot("all-open"));
    assert!(!v.accepted);
    assert_eq!(v.programme_state, "open");

    let mut expected = Vec::new();
    for r in p.required() {
        if r.role != Role::Programme {
            expected.push((r.repo.clone(), r.number, "open".to_string()));
        }
        for reason in [UNCHECKED_1, NOT_RUN, PROPOSED] {
            expected.push((r.repo.clone(), r.number, reason.to_string()));
        }
    }
    assert_eq!(blockers(&v), expected);
    assert_eq!(v.blockers.len(), 3 + 29 * 4);
    assert!(v.waived.is_empty() && v.ignored_waivers.is_empty());
}

#[test]
fn closed_missing_evidence_names_exactly_three_blockers() {
    let v = evaluate(&policy(), &snapshot("closed-missing-evidence"));
    assert!(!v.accepted);
    assert_eq!(v.programme_state, "closed");
    assert_eq!(
        blockers(&v),
        vec![
            b("allen", 2, UNCHECKED_1),
            b("allen", 3, "closed as not_planned, not completed"),
            b("aienos-mv", 396, "open"),
        ]
    );
    assert_eq!(v.blockers[0].role, Role::Phase);
    assert_eq!(v.blockers[0].label, "P0");
    assert_eq!(v.blockers[1].label, "P1");
    assert_eq!(v.blockers[2].role, Role::Prerequisite);
}

#[test]
fn fully_accepted_has_no_blockers() {
    let v = evaluate(&policy(), &snapshot("fully-accepted"));
    assert!(v.accepted, "{:?}", v.blockers);
    assert!(v.blockers.is_empty());
    assert_eq!(v.required, 30);
}

#[test]
fn waivers_apply_to_prerequisite_bodies_only() {
    let v = evaluate(&policy(), &snapshot("waivers"));
    assert!(!v.accepted);
    // P2 carries the waiver label and an unchecked box: the label is ignored.
    // protocols#27 is waived and closed completed: its open boxes and NOT_RUN
    // markers are skipped. omega#505 is waived but open: still blocked.
    assert_eq!(
        blockers(&v),
        vec![b("allen", 4, UNCHECKED_1), b("omega-mv", 505, "open")]
    );
    let waived: Vec<u64> = v.waived.iter().map(|w| w.number).collect();
    assert_eq!(waived, vec![27, 505]);
    let ignored: Vec<u64> = v.ignored_waivers.iter().map(|w| w.number).collect();
    assert_eq!(ignored, vec![4]);
}

#[test]
fn missing_issues_are_blockers_not_acceptances() {
    let snap: Vec<Issue> = snapshot("fully-accepted")
        .into_iter()
        .filter(|i| !(i.number == 1 || (i.repo == "aien-dev/aegis-runtime-mv" && i.number == 53)))
        .collect();
    let v = evaluate(&policy(), &snap);
    assert!(!v.accepted);
    assert_eq!(v.programme_state, "not fetched");
    assert_eq!(
        blockers(&v),
        vec![
            b("allen", 1, "not fetched"),
            b("aegis-runtime-mv", 53, "not fetched")
        ]
    );
    // An empty snapshot blocks on all thirty.
    assert_eq!(evaluate(&policy(), &[]).blockers.len(), 30);
}

#[test]
fn closed_without_reason_and_unknown_state_block() {
    let mut snap = snapshot("fully-accepted");
    snap[2].state_reason = None; // P1
    snap[3].state = "locked".into(); // P2
    snap[4].state_reason = Some("duplicate".into()); // P3
    let v = evaluate(&policy(), &snap);
    assert_eq!(
        blockers(&v),
        vec![
            b("allen", 3, "closed without state_reason completed"),
            b("allen", 4, "unknown state \"locked\""),
            b("allen", 5, "closed as duplicate, not completed"),
        ]
    );
}

#[test]
fn repo_names_match_case_insensitively() {
    let mut snap = snapshot("fully-accepted");
    for i in &mut snap {
        i.repo = i.repo.to_uppercase();
    }
    assert!(evaluate(&policy(), &snap).accepted);
}

#[test]
fn markdown_lists_blockers_and_the_override_rule_without_issue_text() {
    let p = policy();
    let v = evaluate(&p, &snapshot("closed-missing-evidence"));
    let md = render_markdown(&v, &p);
    assert!(md.starts_with("## Programme close guard: not accepted"));
    assert!(md.contains("| aien-dev/allen#2 | phase | P0 | 1 unchecked task-list item(s) |"));
    assert!(md.contains("| aien-dev/allen#3 | phase | P1 | closed as not_planned, not completed |"));
    assert!(md.contains(
        "| aien-dev/aienos-mv#396 | prerequisite | Physical Pi to Spark execution and independent acceptance | open |"
    ));
    assert!(md.contains("never counts as passing"));
    assert!(!md.contains("Synthetic fixture issue body"));

    let ok = evaluate(&p, &snapshot("fully-accepted"));
    let md = render_markdown(&ok, &p);
    assert!(md.starts_with("## Programme close guard: accepted"));
    assert!(md.contains("docs/CLOSE_CHECKLIST.md"));

    let w = evaluate(&p, &snapshot("waivers"));
    let md = render_markdown(&w, &p);
    assert!(md.contains("- aien-dev/aien-protocols-mv#27"));
    assert!(md.contains("Waiver labels ignored"));
}
