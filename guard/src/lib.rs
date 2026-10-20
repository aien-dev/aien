//! allen-guard: the Allen programme close guard and the source-control guard.
//!
//! * [`close`] evaluates whether the programme tracker may stay closed, from a
//!   snapshot of issues. Pure: no network, no GitHub.
//! * [`live`] builds that snapshot through `gh api` (a subprocess, so both the
//!   workflow's `GITHUB_TOKEN` and a developer's `gh` login work).
//! * [`scan`] refuses raw logs, weights and secrets in a working tree, a set of
//!   paths, or the git index (pre-commit).

pub mod close;
pub mod glob;
pub mod live;
pub mod policy;
pub mod scan;

use sha2::{Digest, Sha256};

/// Lowercase hex SHA-256 of `bytes`.
pub fn sha256_hex(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    digest.iter().map(|b| format!("{b:02x}")).collect()
}
