//! Source-control guard on the synthetic fixtures in tests/fixtures/scan.
//! Each fixture is scanned directly with the compiled-in defaults (no
//! allowlist), so every planted problem must be found.

use allen_guard::scan::{scan_bytes, scan_paths, Finding, ScanConfig};
use std::path::PathBuf;

fn fixtures() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/scan")
}

fn scan_fixture(name: &str, cfg: &ScanConfig) -> Vec<(String, usize, String)> {
    let dir = fixtures().join(name);
    // Integration tests run in the crate directory, so paths come back
    // relative to it.
    let prefix = format!("tests/fixtures/scan/{name}/");
    let mut found: Vec<(String, usize, String)> = scan_paths(&[dir], cfg)
        .unwrap()
        .into_iter()
        .map(|f| (f.path.replace(&prefix, ""), f.line, f.rule))
        .collect();
    found.sort();
    found
}

fn f(path: &str, line: usize, rule: &str) -> (String, usize, String) {
    (path.to_string(), line, rule.to_string())
}

#[test]
fn clean_fixture_has_no_findings() {
    assert_eq!(scan_fixture("clean", &ScanConfig::default()), vec![]);
}

#[test]
fn agent_archive_records_are_found() {
    assert_eq!(
        scan_fixture("agent-record", &ScanConfig::default()),
        vec![
            f("archive.jsonl", 1, "agent-record"),
            f("archive.jsonl", 2, "agent-record"),
            f("archive.jsonl", 3, "agent-record"),
        ]
    );
}

#[test]
fn claude_and_codex_session_shapes_are_found() {
    assert_eq!(
        scan_fixture("claude-session", &ScanConfig::default()),
        vec![
            f("session.jsonl", 1, "session-file"),
            f("session.jsonl", 2, "session-file"),
        ]
    );
    assert_eq!(
        scan_fixture("codex-session", &ScanConfig::default()),
        vec![
            f("rollout.jsonl", 1, "session-file"),
            f("rollout.jsonl", 2, "session-file"),
        ]
    );
}

#[test]
fn record_shapes_only_checked_in_head_window() {
    let cfg = ScanConfig {
        head_lines: 1,
        ..ScanConfig::default()
    };
    assert_eq!(
        scan_fixture("agent-record", &cfg),
        vec![f("archive.jsonl", 1, "agent-record")]
    );
}

#[test]
fn every_weight_and_database_extension_is_found() {
    let found = scan_fixture("weights", &ScanConfig::default());
    let mut expected: Vec<_> = [
        "bin",
        "ckpt",
        "db",
        "gguf",
        "npy",
        "npz",
        "pt",
        "pth",
        "safetensors",
        "sqlite",
        "sqlite3",
    ]
    .iter()
    .map(|e| f(&format!("fixture.{e}"), 0, "weight-or-db"))
    .collect();
    expected.sort();
    assert_eq!(found, expected);
}

#[test]
fn every_secret_kind_is_found() {
    assert_eq!(
        scan_fixture("secrets", &ScanConfig::default()),
        vec![
            f("fake-credentials.txt", 2, "secret:github-token"),
            f("fake-credentials.txt", 3, "secret:github-token"),
            f("fake-credentials.txt", 4, "secret:github-token"),
            f("fake-credentials.txt", 5, "secret:github-token"),
            f("fake-credentials.txt", 6, "secret:openai-key"),
            f("fake-credentials.txt", 7, "secret:aws-access-key"),
            f("fake-credentials.txt", 8, "secret:slack-token"),
            f("fake-credentials.txt", 9, "secret:google-api-key"),
            f("fake-credentials.txt", 10, "secret:private-key"),
            f("fake-credentials.txt", 13, "secret:generic-credential"),
        ]
    );
}

#[test]
fn secret_excerpts_are_redacted() {
    let dir = fixtures().join("secrets");
    let text = std::fs::read_to_string(dir.join("fake-credentials.txt")).unwrap();
    for finding in scan_paths(&[dir], &ScanConfig::default()).unwrap() {
        let shown = finding.excerpt.split("... (").next().unwrap();
        assert!(shown.chars().count() <= 12, "{finding}");
        assert!(finding.excerpt.ends_with(" chars)"), "{finding}");
        // The excerpt never reproduces a full line of the fixture.
        assert!(!text
            .lines()
            .any(|l| l.len() > 12 && finding.excerpt.contains(l)));
    }
}

#[test]
fn every_forbidden_directory_is_found() {
    let found = scan_fixture("forbidden-path", &ScanConfig::default());
    let mut expected: Vec<_> = [
        ".claude", ".codex", ".gemini", ".hermes", "latest", "raw", "records", "state",
    ]
    .iter()
    .map(|d| f(&format!("{d}/note.txt"), 0, "forbidden-path"))
    .collect();
    expected.sort();
    assert_eq!(found, expected);
}

#[test]
fn transcript_over_threshold_is_found_with_counts_only() {
    let dir = fixtures().join("transcript");
    let found = scan_paths(&[dir], &ScanConfig::default()).unwrap();
    assert_eq!(found.len(), 1);
    assert_eq!(found[0].rule, "suspected-transcript");
    assert_eq!(found[0].line, 1);
    assert_eq!(found[0].excerpt, "22 chat-turn lines > threshold 20");
}

#[test]
fn size_cap_applies_unless_allowlisted() {
    assert_eq!(scan_fixture("size-cap", &ScanConfig::default()), vec![]);
    let small = ScanConfig {
        size_cap_bytes: 1024,
        ..ScanConfig::default()
    };
    assert_eq!(
        scan_fixture("size-cap", &small),
        vec![f("large.txt", 0, "size-cap")]
    );
    let mut allowed = small.clone();
    allowed.allow.size = vec!["**/size-cap/large.txt".into()];
    assert_eq!(scan_fixture("size-cap", &allowed), vec![]);
}

#[test]
fn default_cap_is_two_mebibytes() {
    let dir = std::env::temp_dir().join(format!("allen-guard-size-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let at_cap = dir.join("at-cap.txt");
    let over = dir.join("over-cap.txt");
    std::fs::write(&at_cap, vec![b'a'; 2 * 1024 * 1024]).unwrap();
    std::fs::write(&over, vec![b'a'; 2 * 1024 * 1024 + 1]).unwrap();
    let cfg = ScanConfig::default();
    assert!(scan_paths(&[at_cap], &cfg).unwrap().is_empty());
    let found = scan_paths(&[over], &cfg).unwrap();
    std::fs::remove_dir_all(&dir).unwrap();
    assert_eq!(found.len(), 1);
    assert_eq!(found[0].rule, "size-cap");
}

#[test]
fn repository_config_allowlists_fixtures_but_not_elsewhere() {
    let cfg =
        ScanConfig::load(&PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("scan.toml")).unwrap();
    let bytes = std::fs::read(fixtures().join("secrets/fake-credentials.txt")).unwrap();
    let n = bytes.len() as u64;
    assert!(scan_bytes(
        "guard/tests/fixtures/scan/secrets/fake-credentials.txt",
        n,
        &bytes,
        &cfg
    )
    .is_empty());
    let elsewhere: Vec<Finding> = scan_bytes("docs/fake-credentials.txt", n, &bytes, &cfg);
    assert_eq!(elsewhere.len(), 10);
    assert!(!scan_bytes("raw/x.safetensors", 16, b"synthetic16bytes", &cfg).is_empty());
}

#[test]
fn binary_files_skip_text_rules_but_not_extension_rules() {
    let cfg = ScanConfig::default();
    let mut bytes = format!("gho_{}", "x".repeat(36)).into_bytes();
    bytes.push(0);
    assert!(scan_bytes("blob.dat", bytes.len() as u64, &bytes, &cfg).is_empty());
    let found = scan_bytes("w.gguf", bytes.len() as u64, &bytes, &cfg);
    assert_eq!(found.len(), 1);
    assert_eq!(found[0].rule, "weight-or-db");
}
