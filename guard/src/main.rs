//! allen-guard command line. Exit codes:
//! 0 accepted / clean, 2 not accepted / findings, 3 close-check with
//! `gh api` failures (blockers recorded, but the run must be visibly red),
//! 1 usage or other error.

use allen_guard::close::{self, Issue};
use allen_guard::live;
use allen_guard::policy::Policy;
use allen_guard::scan::{self, ScanConfig};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

const USAGE: &str = "\
usage:
  allen-guard close-check --policy <policy.toml> (--snapshot <file.json> | --live [--write-snapshot <file.json>])
                          [--markdown <file.md>]
  allen-guard is-programme --policy <policy.toml> --repo <owner/name> --number <n>
  allen-guard scan [--config <scan.toml>] [--json] [--index] [paths...]

close-check prints the JSON verdict on stdout; exit 0 accepted, 2 not accepted,
3 not accepted because gh api failed for some issue, 1 error.
scan walks the git working tree (tracked + untracked, not ignored) when no
paths are given; --index scans the staged content of the given paths.
Exit 0 clean, 2 findings, 1 error.";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = match args.first().map(String::as_str) {
        Some("close-check") => close_check(&args[1..]),
        Some("is-programme") => is_programme(&args[1..]),
        Some("scan") => scan_cmd(&args[1..]),
        Some("-h") | Some("--help") | Some("help") => {
            println!("{USAGE}");
            Ok(0)
        }
        _ => Err(USAGE.to_string()),
    };
    match result {
        Ok(code) => ExitCode::from(code),
        Err(e) => {
            eprintln!("allen-guard: {e}");
            ExitCode::from(1)
        }
    }
}

/// Tiny flag parser: `--flag value`, boolean `--flag`, and positionals.
struct Args {
    flags: Vec<(String, Option<String>)>,
    positional: Vec<String>,
}

impl Args {
    fn parse(args: &[String], booleans: &[&str], valued: &[&str]) -> Result<Args, String> {
        let mut flags = Vec::new();
        let mut positional = Vec::new();
        let mut it = args.iter();
        let mut rest_positional = false;
        while let Some(a) = it.next() {
            if rest_positional || !a.starts_with("--") {
                positional.push(a.clone());
            } else if a == "--" {
                rest_positional = true;
            } else if booleans.contains(&a.as_str()) {
                flags.push((a.clone(), None));
            } else if valued.contains(&a.as_str()) {
                let v = it.next().ok_or_else(|| format!("{a} needs a value"))?;
                flags.push((a.clone(), Some(v.clone())));
            } else {
                return Err(format!("unknown flag {a}\n{USAGE}"));
            }
        }
        Ok(Args { flags, positional })
    }

    fn get(&self, name: &str) -> Option<&str> {
        self.flags
            .iter()
            .rev()
            .find(|(f, _)| f == name)
            .and_then(|(_, v)| v.as_deref())
    }

    fn has(&self, name: &str) -> bool {
        self.flags.iter().any(|(f, _)| f == name)
    }

    fn need(&self, name: &str) -> Result<&str, String> {
        self.get(name)
            .ok_or_else(|| format!("{name} is required\n{USAGE}"))
    }
}

fn close_check(args: &[String]) -> Result<u8, String> {
    let a = Args::parse(
        args,
        &["--live"],
        &["--policy", "--snapshot", "--write-snapshot", "--markdown"],
    )?;
    if !a.positional.is_empty() {
        return Err(format!("unexpected argument {}", a.positional[0]));
    }
    let policy = Policy::load(Path::new(a.need("--policy")?))?;
    let (snapshot, fetch_errors) = match (a.has("--live"), a.get("--snapshot")) {
        (true, None) => {
            let (issues, errors) = live::build_snapshot(&policy, live::fetch_issue);
            if let Some(path) = a.get("--write-snapshot") {
                let json = serde_json::to_string_pretty(&issues).map_err(|e| e.to_string())?;
                std::fs::write(path, json + "\n").map_err(|e| format!("{path}: {e}"))?;
            }
            (issues, errors)
        }
        (false, Some(path)) => {
            let text = std::fs::read_to_string(path).map_err(|e| format!("{path}: {e}"))?;
            let issues: Vec<Issue> =
                serde_json::from_str(&text).map_err(|e| format!("{path}: {e}"))?;
            (issues, Vec::new())
        }
        _ => return Err(format!("give exactly one of --snapshot or --live\n{USAGE}")),
    };

    let mut verdict = close::evaluate(&policy, &snapshot);
    for e in &fetch_errors {
        eprintln!("allen-guard: {e}");
    }
    verdict.fetch_errors = fetch_errors;
    let json = serde_json::to_string_pretty(&verdict).map_err(|e| e.to_string())?;
    println!("{json}");
    let md = close::render_markdown(&verdict, &policy);
    match a.get("--markdown") {
        Some(path) => std::fs::write(path, &md).map_err(|e| format!("{path}: {e}"))?,
        None if !verdict.accepted => eprint!("{md}"),
        None => {}
    }
    Ok(if !verdict.fetch_errors.is_empty() {
        3
    } else if verdict.accepted {
        0
    } else {
        2
    })
}

fn is_programme(args: &[String]) -> Result<u8, String> {
    let a = Args::parse(args, &[], &["--policy", "--repo", "--number"])?;
    let policy = Policy::load(Path::new(a.need("--policy")?))?;
    let number: u64 = a
        .need("--number")?
        .parse()
        .map_err(|e| format!("--number: {e}"))?;
    println!("{}", policy.is_programme(a.need("--repo")?, number));
    Ok(0)
}

fn scan_cmd(args: &[String]) -> Result<u8, String> {
    let a = Args::parse(args, &["--json", "--index"], &["--config"])?;
    let cfg = match a.get("--config") {
        Some(p) => ScanConfig::load(Path::new(p))?,
        None if Path::new("guard/scan.toml").is_file() => {
            eprintln!("allen-guard: using guard/scan.toml");
            ScanConfig::load(Path::new("guard/scan.toml"))?
        }
        None => ScanConfig::default(),
    };
    let paths: Vec<PathBuf> = a.positional.iter().map(PathBuf::from).collect();
    let findings = if a.has("--index") {
        scan::scan_index(&paths, &cfg)?
    } else if paths.is_empty() {
        let files = scan::git_worktree_files()?;
        eprintln!(
            "allen-guard: scanning {} files from git ls-files",
            files.len()
        );
        scan::scan_paths(&files, &cfg)?
    } else {
        scan::scan_paths(&paths, &cfg)?
    };
    if a.has("--json") {
        let json = serde_json::to_string_pretty(&findings).map_err(|e| e.to_string())?;
        println!("{json}");
    } else {
        for f in &findings {
            println!("{f}");
        }
    }
    eprintln!("allen-guard: {} finding(s)", findings.len());
    Ok(if findings.is_empty() { 0 } else { 2 })
}
