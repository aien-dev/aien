# Audit scope

Written for an outside, independent security audit. Revision described:
`b02bc7fb8c28bf90803d5bd357d1749cabdfc974` on `main`, 2026-10-29. Everything below is taken from the repository's own files at
that revision; items marked NOT_RUN were not executed while writing this document.

## What this repository is

Allen's project home: mission (`docs/MISSION.md`), phase ledger P0 to P7 (`docs/PHASES.md`) and the
P0 work-stream plan (`docs/PLAN.md`). README states it is pre-alpha and that nothing here is
qualified. The only code at this revision is the goal microjob kernel (Allen #13):
`src/goal_microjobs/kernel.om` (seeded Omega), its build and driver scripts
`scripts/goal_microjobs/build.sh` and `scripts/goal_microjobs/microjobs.sh`, and the offline gate
`tests/goal_microjobs/gate.sh`. There is no hosted CI. `guard/` and `inventory/` contain only
`.gitkeep`; `evidence/goal-microjobs/offline-20261024T182027Z-rdcMbK/` holds one committed gate
run. `docs/SOURCE_MAP.md` and
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
3. `src/goal_microjobs/` (with `scripts/goal_microjobs/`): the security-relevant code. The kernel
   keeps a persistent journal, admits or refuses plans and events, and enforces budgets and
   cancellation; the gate drives it with synthetic workers and verifiers only (no model call,
   nothing leaves the run directory). Trust boundary: `build.sh` compiles it only with the pinned
   historical seeded compiler: Omega checkout `c434565c67552c0b01df2d7f76c1a04287c70560`,
   `build/L574/toolchain/build/bootstrap/omc` sha256
   `191b776ef98821597c3e30655da6d680a9b66edbc9ceaca3c39c61ea6df098e9`, compiler source
   `seed/omc/omc.om` sha256 `8608fa11f6a2cf1c50db22d871eef16b00d5bc719bc1a222cc3e456984ac5ebf`.
   That toolchain is an untracked build artifact, not part of the Omega commit; `build.sh` exits
   BLOCKED rather than substitute another compiler. The compiler binary itself is trusted, not
   audited here.
4. `docs/PLAN.md`: defines the planned `guards` stream (Rust crate `allen-guard`). It is not on
   `main`.
5. `docs/PHASES.md` and `docs/MISSION.md`: status claims. Check none claims a gate or guard ran.

There is no `.github/workflows/` directory at this revision: no hosted CI exists.

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

`OMEGA_WORKTREE=<seeded omega at c434565c> bash scripts/goal_microjobs/build.sh` builds the
kernel to `target/goal_microjobs/kernel` with the pinned compiler above.

## Run every test

One offline gate, run locally (no hosted CI):

    OMEGA_WORKTREE=<seeded omega at c434565c> GM_RUN_ROOT=<scratch> bash tests/goal_microjobs/gate.sh

It builds the kernel, drives a 12-node objective through the journal across separate processes
(restart, partial completion, model failure, correction, refusal, cancellation, budgets), refuses
plan and event mutants, and checks that kernel source mutations are caught; success prints
`PASS <receipt.json> checks=158`. Observed 2026-10-30 on the Spark against this revision with the
pinned toolchain: PASS, checks=158. The planned source-control guard and programme close guard are
NOT_RUN because they do not exist on `main`.

## Known limitations and NOT_RUN

- `guard/`, `inventory/`: placeholders only.
- The gate's workers and verifiers are synthetic fixtures; no real model or network path is tested.
- Source-control guard: planned, not present; public visibility preceded it.
- `docs/SOURCE_MAP.md`, `docs/B0_ACCEPTANCE_CONTRACT.md`: planned, not on `main`.

## Dependencies and provenance

No lockfile, no vendored code, no GitHub Actions. The one build dependency is the pinned
historical seeded Omega compiler described above. AGENTS.md: outside tools are
yardsticks or test oracles, never shipped.

## Evidence

README: every claim links to a file under `evidence/` or to a receipt in
`aien-dev/aien-receipts`; a sentence with no link is a plan, not a result. `evidence/` holds one
committed gate run, `evidence/goal-microjobs/offline-20261024T182027Z-rdcMbK/` (the gate writes
new runs under `GM_RUN_ROOT`, default `evidence/goal-microjobs/`). Receipts are append-only and are not edited after the fact.
