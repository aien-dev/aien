//! Source-control guard: refuse raw logs, weights and secrets.
//!
//! Rules (rule ids appear in every finding):
//! * `agent-record`: a JSON line shaped like an agent-archive record
//!   (`role` and `text` plus at least three of `ts`, `agent`, `host`,
//!   `session`, `src`), in the first `head_lines` lines of a text file.
//! * `session-file`: a JSON line shaped like a Claude session record
//!   (`"type":"user"|"assistant"` with a `message` object) or a Codex rollout
//!   record (`"type":"response_item"|"session_meta"`), same window.
//! * `size-cap`: file larger than `size_cap_bytes` unless allowlisted.
//! * `weight-or-db`: weight or database file extension.
//! * `secret:<kind>`: credential patterns (adapted from
//!   aien-sovereign-core-mv `crates/spark-aegis/src/scanner.rs` at c83eb5b).
//! * `forbidden-path`: a directory component such as `raw/` or `.claude/`.
//! * `suspected-transcript`: more than `transcript_threshold` lines that look
//!   like chat turns (`user:`, `assistant>`, `Drake:`, `Allen:`).
//!
//! Findings never carry the full match. Secret findings show the first 12
//! characters and the length; record and transcript findings show only the
//! shape and the length, never message text.

use crate::glob;
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::LazyLock;

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields, default)]
pub struct ScanConfig {
    /// Lines checked for record and session shapes at the top of each file.
    pub head_lines: usize,
    pub size_cap_bytes: u64,
    /// More transcript-like lines than this is a finding.
    pub transcript_threshold: usize,
    /// Extensions (without the dot, lowercase) refused outright.
    pub weight_extensions: Vec<String>,
    /// Directory names refused anywhere in a path.
    pub forbidden_components: Vec<String>,
    pub allow: Allow,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(deny_unknown_fields, default)]
pub struct Allow {
    /// Globs skipped by every rule.
    pub paths: Vec<String>,
    /// Globs exempt from `size-cap` only.
    pub size: Vec<String>,
    /// Globs exempt from `forbidden-path` only.
    pub components: Vec<String>,
}

impl Default for ScanConfig {
    fn default() -> Self {
        ScanConfig {
            head_lines: 200,
            size_cap_bytes: 2 * 1024 * 1024,
            transcript_threshold: 20,
            weight_extensions: [
                "safetensors",
                "gguf",
                "pt",
                "pth",
                "bin",
                "ckpt",
                "npy",
                "npz",
                "db",
                "sqlite",
                "sqlite3",
            ]
            .map(String::from)
            .to_vec(),
            forbidden_components: [
                "raw", "records", "latest", "state", ".claude", ".codex", ".gemini", ".hermes",
            ]
            .map(String::from)
            .to_vec(),
            allow: Allow::default(),
        }
    }
}

impl ScanConfig {
    pub fn load(path: &Path) -> Result<ScanConfig, String> {
        let text = std::fs::read_to_string(path)
            .map_err(|e| format!("scan config {}: {e}", path.display()))?;
        toml::from_str(&text).map_err(|e| format!("scan config {}: {e}", path.display()))
    }
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct Finding {
    pub path: String,
    /// 1-based line, or 0 for a whole-file finding.
    pub line: usize,
    pub rule: String,
    pub excerpt: String,
}

impl std::fmt::Display for Finding {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "{}:{}: {}: {}",
            self.path, self.line, self.rule, self.excerpt
        )
    }
}

struct SecretRule {
    kind: &'static str,
    re: Regex,
}

static SECRETS: LazyLock<Vec<SecretRule>> = LazyLock::new(|| {
    let rules: [(&str, &str); 7] = [
        (
            "github-token",
            r"\b(?:ghp|gho|ghu|ghs|ghr)_[0-9A-Za-z]{36}\b|\bgithub_pat_[0-9A-Za-z_]{22,255}\b",
        ),
        (
            "openai-key",
            r"\bsk-(?:proj-|svcacct-|admin-)?[A-Za-z0-9_\-]{20,}",
        ),
        ("aws-access-key", r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"),
        ("slack-token", r"\bxox[abposr]-[0-9A-Za-z\-]{10,}"),
        ("google-api-key", r"\bAIza[0-9A-Za-z_\-]{35}"),
        (
            "private-key",
            r"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY(?: BLOCK)?-----",
        ),
        (
            "generic-credential",
            r#"(?i)\b(?:password|passwd|token|secret|api[_-]?key)\s*[:=]\s*(?:"[^"\s$]{16,}"|'[^'\s$]{16,}'|[A-Za-z0-9+/_\-.]{20,})"#,
        ),
    ];
    rules
        .iter()
        .map(|(kind, re)| SecretRule {
            kind,
            re: Regex::new(re).expect("secret regex"),
        })
        .collect()
});

static TRANSCRIPT: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)^(?:user|assistant|drake|allen)\s*[:>]").unwrap());

const ARCHIVE_EXTRA_KEYS: [&str; 5] = ["ts", "agent", "host", "session", "src"];

/// First 12 characters of `s` plus its length; never the whole value.
pub fn redact(s: &str) -> String {
    let n = s.chars().count();
    let head: String = s.chars().take(12).collect();
    format!("{head}... ({n} chars)")
}

/// Normalise a path for reporting and allowlist matching.
pub fn display_path(p: &Path) -> String {
    let s = p.to_string_lossy().replace('\\', "/");
    s.strip_prefix("./").unwrap_or(&s).to_string()
}

/// Scan one file whose bytes are `head` (the whole file, or its first
/// `size_cap_bytes` when larger and not size-allowlisted) and whose full
/// size is `size`.
pub fn scan_bytes(path: &str, size: u64, head: &[u8], cfg: &ScanConfig) -> Vec<Finding> {
    let mut out = Vec::new();
    if glob::any_match(&cfg.allow.paths, path) {
        return out;
    }
    let whole = |rule: &str, excerpt: String| Finding {
        path: path.to_string(),
        line: 0,
        rule: rule.to_string(),
        excerpt,
    };

    if !glob::any_match(&cfg.allow.components, path) {
        let comps: Vec<&str> = path.split('/').collect();
        if let Some((_, dirs)) = comps.split_last() {
            for d in dirs {
                if cfg.forbidden_components.iter().any(|c| c == d) {
                    out.push(whole("forbidden-path", format!("directory {d}/")));
                }
            }
        }
    }
    if size > cfg.size_cap_bytes && !glob::any_match(&cfg.allow.size, path) {
        out.push(whole(
            "size-cap",
            format!("{size} bytes > cap {} bytes", cfg.size_cap_bytes),
        ));
    }
    if let Some(ext) = Path::new(path).extension().and_then(|e| e.to_str()) {
        let ext = ext.to_ascii_lowercase();
        if cfg.weight_extensions.contains(&ext) {
            out.push(whole("weight-or-db", format!(".{ext} file, {size} bytes")));
        }
    }

    let sniff = &head[..head.len().min(8192)];
    if sniff.contains(&0) {
        return out; // binary: text rules do not apply
    }
    let text = String::from_utf8_lossy(head);
    let mut transcript_lines = 0usize;
    let mut first_transcript = 0usize;
    for (i, line) in text.lines().enumerate() {
        let lineno = i + 1;
        let at = |rule: String, excerpt: String| Finding {
            path: path.to_string(),
            line: lineno,
            rule,
            excerpt,
        };
        if i < cfg.head_lines {
            if let Some(rule) = record_shape(line) {
                out.push(at(
                    rule.into(),
                    format!("<json record line> ({} chars)", line.chars().count()),
                ));
            }
        }
        for s in SECRETS.iter() {
            for m in s.re.find_iter(line) {
                out.push(at(format!("secret:{}", s.kind), redact(m.as_str())));
            }
        }
        if TRANSCRIPT.is_match(line.trim_start()) {
            transcript_lines += 1;
            if first_transcript == 0 {
                first_transcript = lineno;
            }
        }
    }
    if transcript_lines > cfg.transcript_threshold {
        out.push(Finding {
            path: path.to_string(),
            line: first_transcript,
            rule: "suspected-transcript".into(),
            excerpt: format!(
                "{transcript_lines} chat-turn lines > threshold {}",
                cfg.transcript_threshold
            ),
        });
    }
    out
}

fn record_shape(line: &str) -> Option<&'static str> {
    let t = line.trim();
    if !t.starts_with('{') {
        return None;
    }
    let serde_json::Value::Object(obj) = serde_json::from_str::<serde_json::Value>(t).ok()? else {
        return None;
    };
    if obj.contains_key("role") && obj.contains_key("text") {
        let extra = ARCHIVE_EXTRA_KEYS
            .iter()
            .filter(|k| obj.contains_key(**k))
            .count();
        if extra >= 3 {
            return Some("agent-record");
        }
    }
    match obj.get("type").and_then(|v| v.as_str()) {
        Some("user") | Some("assistant") if obj.get("message").is_some_and(|m| m.is_object()) => {
            Some("session-file")
        }
        Some("response_item") | Some("session_meta") => Some("session-file"),
        _ => None,
    }
}

/// Read a working-tree file and scan it. `checked` is the repository-relative
/// path the rules and allowlists judge (see [`scan_paths`]).
pub fn scan_file(path: &Path, checked: &str, cfg: &ScanConfig) -> Result<Vec<Finding>, String> {
    let size = std::fs::metadata(path)
        .map_err(|e| format!("{checked}: {e}"))?
        .len();
    let limit = read_limit(checked, size, cfg);
    let mut head = Vec::new();
    std::fs::File::open(path)
        .and_then(|f| f.take(limit).read_to_end(&mut head))
        .map_err(|e| format!("{checked}: {e}"))?;
    Ok(scan_bytes(checked, size, &head, cfg))
}

fn read_limit(shown: &str, size: u64, cfg: &ScanConfig) -> u64 {
    if glob::any_match(&cfg.allow.size, shown) {
        size
    } else {
        size.min(cfg.size_cap_bytes)
    }
}

/// The path the rules judge for a scan argument: relative arguments as
/// given; absolute arguments relative to the current directory when inside
/// it, otherwise anchored at their own last component. Directories above the
/// scan root (for example a clone kept under `~/.hermes/`) are not judged.
fn anchor(p: &Path) -> String {
    if !p.is_absolute() {
        return display_path(p);
    }
    if let Ok(cwd) = std::env::current_dir() {
        if let Ok(rel) = p.strip_prefix(&cwd) {
            let rel = display_path(rel);
            return if rel.is_empty() { ".".into() } else { rel };
        }
    }
    p.file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default()
}

/// Scan files and directories (recursively, skipping `.git` and `target`,
/// not following symlinks).
pub fn scan_paths(paths: &[PathBuf], cfg: &ScanConfig) -> Result<Vec<Finding>, String> {
    let mut out = Vec::new();
    for p in paths {
        walk(p, &anchor(p), cfg, &mut out)?;
    }
    Ok(out)
}

fn walk(p: &Path, checked: &str, cfg: &ScanConfig, out: &mut Vec<Finding>) -> Result<(), String> {
    let meta = std::fs::symlink_metadata(p).map_err(|e| format!("{checked}: {e}"))?;
    if meta.file_type().is_symlink() {
        return Ok(());
    }
    if meta.is_dir() {
        let mut entries: Vec<PathBuf> = std::fs::read_dir(p)
            .map_err(|e| format!("{checked}: {e}"))?
            .filter_map(|e| e.ok().map(|e| e.path()))
            .collect();
        entries.sort();
        for e in entries {
            let name = e.file_name().and_then(|n| n.to_str()).unwrap_or("");
            if e.is_dir() && (name == ".git" || name == "target") {
                continue;
            }
            let child = match checked {
                "" | "." => name.to_string(),
                c => format!("{}/{name}", c.trim_end_matches('/')),
            };
            walk(&e, &child, cfg, out)?;
        }
        return Ok(());
    }
    out.extend(scan_file(p, checked, cfg)?);
    Ok(())
}

/// Files git would commit from here: tracked plus untracked-not-ignored.
pub fn git_worktree_files() -> Result<Vec<PathBuf>, String> {
    let out = Command::new("git")
        .args([
            "ls-files",
            "-z",
            "--cached",
            "--others",
            "--exclude-standard",
        ])
        .output()
        .map_err(|e| format!("git ls-files: {e}"))?;
    if !out.status.success() {
        return Err("git ls-files failed (not a git checkout?)".into());
    }
    Ok(out
        .stdout
        .split(|b| *b == 0)
        .filter(|s| !s.is_empty())
        .map(|s| PathBuf::from(String::from_utf8_lossy(s).into_owned()))
        .filter(|p| p.symlink_metadata().is_ok_and(|m| m.is_file()))
        .collect())
}

/// Scan the staged (index) content of `paths`, as the commit would record it.
pub fn scan_index(paths: &[PathBuf], cfg: &ScanConfig) -> Result<Vec<Finding>, String> {
    let mut out = Vec::new();
    for p in paths {
        let shown = display_path(p);
        let spec = format!(":{shown}");
        let size_out = Command::new("git")
            .args(["cat-file", "-s", &spec])
            .output()
            .map_err(|e| format!("git cat-file: {e}"))?;
        if !size_out.status.success() {
            return Err(format!("{shown}: not in the index"));
        }
        let size: u64 = String::from_utf8_lossy(&size_out.stdout)
            .trim()
            .parse()
            .map_err(|e| format!("{shown}: size: {e}"))?;
        let mut child = Command::new("git")
            .args(["cat-file", "blob", &spec])
            .stdout(std::process::Stdio::piped())
            .spawn()
            .map_err(|e| format!("git cat-file: {e}"))?;
        let mut head = Vec::new();
        if let Some(stdout) = child.stdout.take() {
            stdout
                .take(read_limit(&shown, size, cfg))
                .read_to_end(&mut head)
                .map_err(|e| format!("{shown}: {e}"))?;
        }
        let _ = child.kill();
        let _ = child.wait();
        out.extend(scan_bytes(&shown, size, &head, cfg));
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redaction_keeps_twelve_chars() {
        let fake = format!("gho_{}", "x".repeat(36));
        assert_eq!(redact(&fake), "gho_xxxxxxxx... (40 chars)");
    }

    #[test]
    fn generic_credential_needs_a_literal() {
        let cfg = ScanConfig::default();
        let clean = "let token = std::env::var(\"GH_TOKEN\");\nGH_TOKEN: ${{ github.token }}\npassword = prompt()\n";
        assert!(scan_bytes("a.rs", 10, clean.as_bytes(), &cfg).is_empty());
        let dirty = format!("password = \"{}\"\n", "y".repeat(20));
        let f = scan_bytes("a.rs", 10, dirty.as_bytes(), &cfg);
        assert_eq!(f.len(), 1);
        assert_eq!(f[0].rule, "secret:generic-credential");
    }

    #[test]
    fn transcript_threshold_is_strictly_greater() {
        let cfg = ScanConfig::default();
        let at = "user: synthetic\n".repeat(20);
        assert!(scan_bytes("t.md", 10, at.as_bytes(), &cfg).is_empty());
        let over = "user: synthetic\n".repeat(21);
        assert_eq!(scan_bytes("t.md", 10, over.as_bytes(), &cfg).len(), 1);
    }
}
