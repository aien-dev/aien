# Security policy

## Reporting a vulnerability

Report privately. Do not open a public issue, pull request or discussion about it.

1. GitHub: open this repository's Security tab and choose "Report a vulnerability". This
   creates a private advisory that only the maintainers can see. If that option is not shown,
   private vulnerability reporting has not been enabled for this repository yet; use email.
2. Email: drake@aienos.com with the subject `[aien] security report`.

Include the commit or release you tested, the component (path), steps to reproduce, and what an
attacker gains. If the report involves a secret, say where it was exposed and do not send the
secret itself. Encrypted mail is not required; do not post proof-of-concept payloads publicly.

## Response targets

This project has one maintainer; the targets below are best effort and stated honestly.

- Acknowledgement: within 3 working days.
- Triage and severity: within 7 days of acknowledgement.
- Fix or mitigation for confirmed issues: aim for 30 days for high and critical, 90 days
  otherwise, with a status update at least every 14 days until closed.
- Disclosure: coordinated. An advisory is published with credit (unless you ask otherwise)
  once the fix is on the default branch. Default embargo 90 days, negotiable.

## Scope

This repository holds Allen's mission, phase ledger and plans. At this revision it has no code:
`docs/MISSION.md`, `docs/PHASES.md`, `docs/PLAN.md`, `README.md`, `AGENTS.md`, a `.gitignore`
and empty `.gitkeep` placeholders in `evidence/`, `guard/`, `inventory/` and `scripts/`.

In scope:

- Raw conversations, credentials, weights, private training samples or personal data in any file,
  branch, issue or pull request. AGENTS.md says these never enter this repository.
- Private host names, paths or addresses that disclose where access-controlled data lives beyond
  what the repository already states as a pointer.
- Once they land: the planned Rust `allen-guard` crate (`guard/`) and its workflows, which are
  meant to refuse raw logs, weights and secrets.

Out of scope:

- Allen's identity object, Cortex memory, runtime authority and protocols. README names their
  owning repositories; report there.
- The access-controlled conversation archive itself, which is not in this repository.

## Supported versions

Only the default branch `main`; there is no release. Reports against older commits are welcome but fixes land on the default branch only.

## Status

Pre-alpha. README: "Nothing here is qualified." The planned programme close guard and
source-control guard are not on `main`; public visibility is not evidence that a safeguard ran.
No certification, no bug bounty. See AUDIT_SCOPE.md for what to review and how to build and test it.
