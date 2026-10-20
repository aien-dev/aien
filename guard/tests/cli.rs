//! The allen-guard binary: exit codes, live mode through a fake `gh`, index
//! scanning and the pre-commit hook in a throwaway git repository.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_allen-guard")
}

fn crate_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn policy() -> String {
    crate_dir()
        .join("policy.toml")
        .to_string_lossy()
        .into_owned()
}

fn snapshot(name: &str) -> String {
    crate_dir()
        .join("tests/fixtures/close")
        .join(format!("{name}.json"))
        .to_string_lossy()
        .into_owned()
}

fn temp_dir(tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("allen-guard-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn verdict(out: &Output) -> serde_json::Value {
    serde_json::from_slice(&out.stdout).expect("stdout is the JSON verdict")
}

#[test]
fn close_check_exit_codes_follow_the_verdict() {
    for (name, code, accepted) in [
        ("all-open", 2, false),
        ("closed-missing-evidence", 2, false),
        ("fully-accepted", 0, true),
        ("waivers", 2, false),
    ] {
        let out = Command::new(bin())
            .args([
                "close-check",
                "--policy",
                &policy(),
                "--snapshot",
                &snapshot(name),
            ])
            .output()
            .unwrap();
        assert_eq!(out.status.code(), Some(code), "{name}");
        assert_eq!(verdict(&out)["accepted"], accepted, "{name}");
    }
}

#[test]
fn close_check_writes_markdown_for_the_comment() {
    let dir = temp_dir("md");
    let md = dir.join("verdict.md");
    let out = Command::new(bin())
        .args(["close-check", "--policy", &policy(), "--snapshot"])
        .arg(snapshot("closed-missing-evidence"))
        .arg("--markdown")
        .arg(&md)
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(2));
    let v = verdict(&out);
    let reasons: Vec<&str> = v["blockers"]
        .as_array()
        .unwrap()
        .iter()
        .map(|b| b["reason"].as_str().unwrap())
        .collect();
    assert_eq!(
        reasons,
        vec![
            "1 unchecked task-list item(s)",
            "closed as not_planned, not completed",
            "open"
        ]
    );
    let text = std::fs::read_to_string(&md).unwrap();
    assert!(text.contains("3 blocker(s)"));
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn bad_input_is_an_error_not_a_verdict() {
    let out = Command::new(bin())
        .args(["close-check", "--policy", &policy()])
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(1));
    let out = Command::new(bin())
        .args([
            "close-check",
            "--policy",
            "/nonexistent.toml",
            "--snapshot",
            &snapshot("all-open"),
        ])
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(1));
    let out = Command::new(bin()).arg("frobnicate").output().unwrap();
    assert_eq!(out.status.code(), Some(1));
}

#[test]
fn live_mode_without_gh_fails_visibly_and_blocks_everything() {
    let out = Command::new(bin())
        .env("ALLEN_GUARD_GH", "/nonexistent/gh")
        .args(["close-check", "--policy", &policy(), "--live"])
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(3));
    let v = verdict(&out);
    assert_eq!(v["accepted"], false);
    assert_eq!(v["fetch_errors"].as_array().unwrap().len(), 30);
    assert!(v["blockers"]
        .as_array()
        .unwrap()
        .iter()
        .all(|b| b["reason"] == "not fetched"));
}

#[cfg(unix)]
fn fake_gh(dir: &Path, fail_endpoint: &str) -> PathBuf {
    use std::os::unix::fs::PermissionsExt;
    let script = dir.join("gh");
    let body = format!(
        r#"#!/bin/sh
# fake gh for allen-guard tests: gh api <endpoint>
[ "$1" = api ] || exit 64
if [ "$2" = "{fail_endpoint}" ]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
cat <<'JSON'
{{"state":"closed","state_reason":"completed","title":"synthetic fixture","body":"- [x] synthetic\nStatus: COMPLETE; qualification: PASS.","labels":[{{"name":"synthetic"}}],"html_url":"https://example.invalid/issue"}}
JSON
"#
    );
    std::fs::write(&script, body).unwrap();
    std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();
    script
}

#[cfg(unix)]
#[test]
fn live_mode_builds_and_saves_a_snapshot() {
    let dir = temp_dir("live");
    let gh = fake_gh(&dir, "none");
    let snap = dir.join("snapshot.json");
    let out = Command::new(bin())
        .env("ALLEN_GUARD_GH", &gh)
        .args([
            "close-check",
            "--policy",
            &policy(),
            "--live",
            "--write-snapshot",
        ])
        .arg(&snap)
        .output()
        .unwrap();
    assert_eq!(
        out.status.code(),
        Some(0),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let saved: Vec<serde_json::Value> =
        serde_json::from_str(&std::fs::read_to_string(&snap).unwrap()).unwrap();
    assert_eq!(saved.len(), 30);
    assert_eq!(saved[0]["repo"], "aien-dev/allen");
    assert_eq!(saved[0]["labels"][0], "synthetic");

    // The saved snapshot re-evaluates to the same verdict.
    let again = Command::new(bin())
        .args(["close-check", "--policy", &policy(), "--snapshot"])
        .arg(&snap)
        .output()
        .unwrap();
    assert_eq!(again.status.code(), Some(0));

    // One failing gh call: exit 3, that issue is a "not fetched" blocker.
    let gh = fake_gh(&dir, "repos/aien-dev/omega-mv/issues/505");
    let out = Command::new(bin())
        .env("ALLEN_GUARD_GH", &gh)
        .args(["close-check", "--policy", &policy(), "--live"])
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(3));
    let v = verdict(&out);
    assert_eq!(v["blockers"].as_array().unwrap().len(), 1);
    assert_eq!(v["blockers"][0]["number"], 505);
    assert_eq!(v["blockers"][0]["reason"], "not fetched");
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn is_programme_answers_true_only_for_the_programme() {
    for (repo, n, want) in [
        ("aien-dev/allen", "1", "true"),
        ("AIEN-DEV/Allen", "1", "true"),
        ("aien-dev/allen", "2", "false"),
        ("aien-dev/other", "1", "false"),
    ] {
        let out = Command::new(bin())
            .args([
                "is-programme",
                "--policy",
                &policy(),
                "--repo",
                repo,
                "--number",
                n,
            ])
            .output()
            .unwrap();
        assert_eq!(out.status.code(), Some(0));
        assert_eq!(
            String::from_utf8_lossy(&out.stdout).trim(),
            want,
            "{repo}#{n}"
        );
    }
}

#[test]
fn scan_exit_codes() {
    let fixtures = crate_dir().join("tests/fixtures/scan");
    let clean = Command::new(bin())
        .arg("scan")
        .arg(fixtures.join("clean"))
        .output()
        .unwrap();
    assert_eq!(clean.status.code(), Some(0));
    let dirty = Command::new(bin())
        .args(["scan", "--json"])
        .arg(&fixtures)
        .output()
        .unwrap();
    assert_eq!(dirty.status.code(), Some(2));
    let findings: Vec<serde_json::Value> = serde_json::from_slice(&dirty.stdout).unwrap();
    // 3 records + 4 session lines + 11 weights + 10 secrets + 8 paths + 1 transcript.
    assert_eq!(findings.len(), 37);
    let stdout = String::from_utf8_lossy(&dirty.stdout);
    assert!(
        !stdout.contains(&"x".repeat(13)),
        "a full fake token leaked into output"
    );
}

fn git(dir: &Path, args: &[&str]) -> Output {
    let out = Command::new("git")
        .current_dir(dir)
        .args(args)
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    out
}

fn init_repo(tag: &str) -> PathBuf {
    let dir = temp_dir(tag);
    git(&dir, &["init", "-q"]);
    git(&dir, &["config", "user.name", "allen-guard test"]);
    git(&dir, &["config", "user.email", "test@example.invalid"]);
    git(&dir, &["config", "commit.gpgsign", "false"]);
    dir
}

#[test]
fn index_scan_reads_staged_content_not_the_working_tree() {
    let dir = init_repo("index");
    let token = format!("gho_{}", "x".repeat(36));
    std::fs::write(dir.join("notes.txt"), "synthetic fixture, clean\n").unwrap();
    git(&dir, &["add", "notes.txt"]);
    // Working tree now has a token, the index does not.
    std::fs::write(dir.join("notes.txt"), format!("leak = {token}\n")).unwrap();
    let run = || {
        Command::new(bin())
            .current_dir(&dir)
            .args(["scan", "--index", "--", "notes.txt"])
            .output()
            .unwrap()
    };
    assert_eq!(run().status.code(), Some(0));
    git(&dir, &["add", "notes.txt"]);
    let out = run();
    assert_eq!(out.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&out.stdout).contains("secret:github-token"));
    std::fs::remove_dir_all(dir).unwrap();
}

#[cfg(unix)]
#[test]
fn pre_commit_hook_refuses_weights_and_secrets_and_allows_clean_commits() {
    let dir = init_repo("hook");
    let scripts = crate_dir().join("../scripts");
    let install = Command::new(scripts.join("install-hooks.sh"))
        .current_dir(&dir)
        .output()
        .unwrap();
    assert!(install.status.success());
    // The installed hook execs <repo>/scripts/pre-commit; provide it.
    std::fs::create_dir_all(dir.join("scripts")).unwrap();
    std::fs::copy(scripts.join("pre-commit"), dir.join("scripts/pre-commit")).unwrap();
    let commit = |msg: &str| {
        Command::new("git")
            .current_dir(&dir)
            .env("ALLEN_GUARD_BIN", bin())
            .args(["commit", "-q", "-m", msg])
            .output()
            .unwrap()
    };

    git(&dir, &["add", "scripts/pre-commit"]);
    std::fs::write(dir.join("README.md"), "synthetic fixture\n").unwrap();
    git(&dir, &["add", "README.md"]);
    assert!(commit("clean").status.success());

    std::fs::write(dir.join("model.safetensors"), "synthetic16bytes").unwrap();
    git(&dir, &["add", "-f", "model.safetensors"]);
    let out = commit("weights");
    assert!(!out.status.success());
    // git sends hook output to stderr.
    assert!(String::from_utf8_lossy(&out.stderr).contains("weight-or-db"));
    git(&dir, &["rm", "-q", "--cached", "model.safetensors"]);

    let token = format!("ghp_{}", "x".repeat(36));
    std::fs::write(dir.join("config.txt"), format!("t = {token}\n")).unwrap();
    git(&dir, &["add", "config.txt"]);
    assert!(!commit("secret").status.success());
    std::fs::remove_dir_all(dir).unwrap();
}

#[cfg(unix)]
#[test]
fn history_scan_catches_a_secret_deleted_in_a_later_commit() {
    let dir = init_repo("history");
    let token = format!("gho_{}", "x".repeat(36));
    let commit = |msg: &str| git(&dir, &["commit", "-q", "--no-verify", "-m", msg]);
    std::fs::write(dir.join("README.md"), "synthetic fixture\n").unwrap();
    git(&dir, &["add", "README.md"]);
    commit("base");
    std::fs::write(dir.join("leak.txt"), format!("t = {token}\n")).unwrap();
    git(&dir, &["add", "leak.txt"]);
    commit("add leak");
    git(&dir, &["rm", "-q", "leak.txt"]);
    commit("remove leak");

    // The tip is clean.
    let tip = Command::new(bin())
        .current_dir(&dir)
        .arg("scan")
        .output()
        .unwrap();
    assert_eq!(tip.status.code(), Some(0));

    // --rev reads the file as that commit recorded it.
    let rev = Command::new(bin())
        .current_dir(&dir)
        .args(["scan", "--rev", "HEAD~1", "--", "leak.txt"])
        .output()
        .unwrap();
    assert_eq!(rev.status.code(), Some(2));

    // scan-history.sh over the range finds it in the middle commit.
    let script = crate_dir().join("../scripts/scan-history.sh");
    let hist = Command::new(&script)
        .current_dir(&dir)
        .env("ALLEN_GUARD_BIN", bin())
        .arg("HEAD~2..HEAD")
        .output()
        .unwrap();
    assert_eq!(hist.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&hist.stdout).contains("leak.txt:1: secret:github-token"));
    assert!(String::from_utf8_lossy(&hist.stderr).contains("scanned 2 commit(s)"));
    let clean = Command::new(&script)
        .current_dir(&dir)
        .env("ALLEN_GUARD_BIN", bin())
        .arg("HEAD~3..HEAD~2")
        .output();
    // HEAD~3 does not exist in a three-commit repository: rev-list errors.
    assert!(!clean.unwrap().status.success());
    let base_only = Command::new(&script)
        .current_dir(&dir)
        .env("ALLEN_GUARD_BIN", bin())
        .arg("HEAD~2")
        .arg("--max-count=1")
        .output()
        .unwrap();
    assert_eq!(base_only.status.code(), Some(0));
    std::fs::remove_dir_all(dir).unwrap();
}
