//! guard/policy.toml must stay in step with docs/PHASES.md.

use allen_guard::policy::{Policy, Role};
use regex::Regex;
use std::collections::BTreeSet;
use std::path::PathBuf;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..")
}

fn policy() -> Policy {
    Policy::load(&repo_root().join("guard/policy.toml")).unwrap()
}

#[test]
fn programme_and_phases_are_allen_1_to_9() {
    let p = policy();
    assert_eq!(
        (p.programme.repo.as_str(), p.programme.number),
        ("aien-dev/allen", 1)
    );
    let phases: Vec<(String, String, u64)> = p
        .phases
        .iter()
        .map(|ph| (ph.name.clone(), ph.repo.clone(), ph.number))
        .collect();
    let expected: Vec<(String, String, u64)> = (0..8)
        .map(|i| (format!("P{i}"), "aien-dev/allen".to_string(), i + 2))
        .collect();
    assert_eq!(phases, expected);
}

/// Parse the "Mandatory external prerequisites" table of docs/PHASES.md.
fn phases_md_prerequisites() -> BTreeSet<(String, u64)> {
    let text = std::fs::read_to_string(repo_root().join("docs/PHASES.md")).unwrap();
    let section = text
        .split("## Mandatory external prerequisites")
        .nth(1)
        .expect("PHASES.md has the prerequisites section");
    let paren = Regex::new(r"\([^)]*\)").unwrap();
    let num = Regex::new(r"#(\d+)").unwrap();
    let mut out = BTreeSet::new();
    for row in section.lines().filter(|l| l.starts_with('|')).skip(2) {
        let cells: Vec<&str> = row.split('|').map(str::trim).collect();
        let issues = paren.replace_all(cells[2], "");
        for segment in issues.split(';') {
            let segment = segment.trim();
            let Some(repo) = segment.split_whitespace().next() else {
                continue;
            };
            for c in num.captures_iter(segment) {
                out.insert((format!("aien-dev/{repo}"), c[1].parse().unwrap()));
            }
        }
    }
    out
}

#[test]
fn prerequisites_match_phases_md_table() {
    let from_policy: BTreeSet<(String, u64)> = policy()
        .required()
        .into_iter()
        .filter(|r| r.role == Role::Prerequisite)
        .map(|r| (r.repo, r.number))
        .collect();
    let from_doc = phases_md_prerequisites();
    assert_eq!(from_doc.len(), 21, "{from_doc:?}");
    assert_eq!(from_policy, from_doc);
}

#[test]
fn rejects_duplicates_and_bad_repos() {
    let dup = "[programme]\nrepo='o/r'\nnumber=1\n[[phases]]\nname='P0'\nrepo='o/r'\nnumber=1\n";
    assert!(Policy::from_toml(dup).unwrap_err().contains("listed twice"));
    let bad = "[programme]\nrepo='nope'\nnumber=1\n[[phases]]\nname='P0'\nrepo='o/r'\nnumber=2\n";
    assert!(Policy::from_toml(bad).is_err());
    let unknown = "[programme]\nrepo='o/r'\nnumber=1\nwaive_everything=true\n[[phases]]\nname='P0'\nrepo='o/r'\nnumber=2\n";
    assert!(Policy::from_toml(unknown).is_err());
}
