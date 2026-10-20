//! Minimal path globs for allowlists: `*` and `?` within one path segment,
//! `**` across any number of segments (including none). Paths use `/`.

pub fn matches(pattern: &str, path: &str) -> bool {
    let pat: Vec<&str> = pattern.trim_start_matches("./").split('/').collect();
    let segs: Vec<&str> = path.trim_start_matches("./").split('/').collect();
    match_segments(&pat, &segs)
}

pub fn any_match(patterns: &[String], path: &str) -> bool {
    patterns.iter().any(|p| matches(p, path))
}

fn match_segments(pat: &[&str], segs: &[&str]) -> bool {
    match pat.split_first() {
        None => segs.is_empty(),
        Some((&"**", rest)) => (0..=segs.len()).any(|i| match_segments(rest, &segs[i..])),
        Some((p, rest)) => match segs.split_first() {
            Some((s, srest)) => {
                match_segment(p.as_bytes(), s.as_bytes()) && match_segments(rest, srest)
            }
            None => false,
        },
    }
}

fn match_segment(p: &[u8], s: &[u8]) -> bool {
    match p.split_first() {
        None => s.is_empty(),
        Some((b'*', rest)) => (0..=s.len()).any(|i| match_segment(rest, &s[i..])),
        Some((b'?', rest)) => !s.is_empty() && match_segment(rest, &s[1..]),
        Some((c, rest)) => s.first() == Some(c) && match_segment(rest, &s[1..]),
    }
}

#[cfg(test)]
mod tests {
    use super::matches;

    #[test]
    fn globs() {
        assert!(matches(
            "guard/tests/fixtures/**",
            "guard/tests/fixtures/scan/raw/a.txt"
        ));
        assert!(matches("guard/tests/fixtures/**", "guard/tests/fixtures"));
        assert!(!matches("guard/tests/fixtures/**", "guard/src/lib.rs"));
        assert!(matches("**/*.lock", "Cargo.lock"));
        assert!(matches("**/*.lock", "a/b/Cargo.lock"));
        assert!(matches("docs/*.md", "docs/PLAN.md"));
        assert!(!matches("docs/*.md", "docs/sub/PLAN.md"));
        assert!(matches(
            "./evidence/guards/?.json",
            "evidence/guards/a.json"
        ));
    }
}
