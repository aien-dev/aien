# Audit scope

Written for an outside, independent security audit. Revision described:
`a36dcfc6b69c338f38ace7c77b3255c4fb2f820c` on `main`, 2026-10-26. Everything below is taken from the repository's own files at
that revision; items marked NOT_RUN were not executed while writing this document.

## What this repository is

Allen's project home: mission (`docs/MISSION.md`), phase ledger P0 to P7 (`docs/PHASES.md`) and the
P0 work-stream plan (`docs/PLAN.md`). README states it is pre-alpha and that nothing here is
qualified. At this revision there is no code, no build, no test and no CI. `guard/`, `inventory/`,
`evidence/` and `scripts/` contain only `.gitkeep`. `docs/SOURCE_MAP.md` and
`docs/B0_ACCEPTANCE_CONTRACT.md` are planned and not on `main`. Licence AGPL-3.0-or-later.

## What an auditor can and cannot check here

- Can check: that no tracked file contains raw conversations, credentials, weights, private
  training samples or personal data; that `.gitignore` excludes the file types the README says
  never enter the repository; that the documents do not overstate status.
- Cannot check here: the source-control guard or programme close guard (planned, not present);
  the access-controlled conversation archive; Allen's identity, memory or runtime, which live in
  other repositories (README table "What lives here and what does not").

## What to review, in priority order

1. The whole tree and its history for leaked private data. AGENTS.md: "The source-control guard
   planned for `guard/` is not on `main`; check this boundary yourself rather than relying on an
   automatic guard." README: the repository was created private on 2026-10-20 and is now publicly
   readable without a green guard receipt.
2. `.gitignore`: excludes `*.jsonl`, `records/`, `raw/`, `latest/`, `state/`, `*.safetensors`,
   `*.gguf`, `*.pt`, `*.bin`, `*.db`, `*.sqlite`, `.env`, `*.pem`, `*.key`, `target/`. Check it
   matches the stated policy. An ignore file is not enforcement.
3. `docs/PLAN.md`: defines the planned `guards` stream (Rust crate `allen-guard`, workflows under
   `.github/workflows/`). When it lands it will be the security-relevant code; none exists now.
4. `docs/PHASES.md` and `docs/MISSION.md`: status claims. Check none claims a gate or guard ran.

There is no `.github/workflows/` directory at this revision.

## Trust boundaries

- Untrusted: issues and pull requests from outside contributors.
- Access-controlled and outside this repository: raw conversation logs, personal training
  artifacts and weights. README says this repository holds pointers, counts and digests only.
- Trusted: the maintainer's review before merge. AGENTS.md: agents push branches and do not open or
  merge pull requests themselves.

## Threat model summary

- Assets: privacy of conversation data and personal training material; honesty of status claims.
- Attackers considered: accidental commit of raw data or secrets; a status claim that overstates
  evidence.
- Defended: written policy in AGENTS.md and README; `.gitignore` patterns; human review.
- Not defended / explicitly out of scope: there is no automatic guard on `main`; status words
  (PASS, FAIL, INCONCLUSIVE, NOT_RUN) are checked manually until the close guard exists.

## Build from source at a pin

Nothing to build at this revision.

## Run every test

There is no test suite and no CI. Every planned check (source-control guard, programme close guard)
is NOT_RUN because it does not exist on `main`.

## Known limitations and NOT_RUN

- `guard/`, `inventory/`, `evidence/`, `scripts/`: placeholders only.
- Source-control guard: planned, not present; public visibility preceded it.
- `docs/SOURCE_MAP.md`, `docs/B0_ACCEPTANCE_CONTRACT.md`: planned, not on `main`.

## Dependencies and provenance

No lockfile, no vendored code, no dependencies, no GitHub Actions. AGENTS.md: outside tools are
yardsticks or test oracles, never shipped.

## Evidence

README: every claim links to a file under `evidence/` or to a receipt in
`aien-dev/aien-receipts`; a sentence with no link is a plan, not a result. `evidence/` is empty
at this revision. Receipts are append-only and are not edited after the fact.
