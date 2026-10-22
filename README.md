<!-- github-native-navigation -->
[Source](https://github.com/aien-dev/allen) · [Replay receipt](docs/teaching-replay.txt) · [Issues](https://github.com/aien-dev/allen/issues)
<!-- /github-native-navigation -->

# Allen

Allen is the persistent subject that the AIEN system sustains: one identity across the iMac, the Raspberry Pi, the DGX Spark and the MacBook (architecture ADR 0035). This repository is Allen's project home: mission, phase ledger (P0 to P7), data contracts, evaluation harness, release manifests and the acceptance contract for the first qualified release, **Allen B0**.

**Pre-alpha.** Nothing here is qualified. Every claim in this repository links to a file under `evidence/` or to a receipt in [aien-dev/aien-receipts](https://github.com/aien-dev/aien-receipts); a sentence with no link is a plan, not a result.

## What lives here and what does not

| Here | Not here (owner) |
|---|---|
| Mission, phase issues P0 to P7, B0 acceptance contract | Allen's identity object, SubjectState kind 24 (aienos-mv, ADR 0018) |
| Log inventory: counts, dates, hosts, gaps | The logs themselves (Spark `~/archive/agent-chats/`, access controlled) |
| Data contracts and synthetic fixtures | Raw conversations, trained weights, secrets (never in any repository) |
| Evaluation harness and release manifests (digests, pins) | Memory (Cortex, ADR 0022), runtime authority (aegis-runtime-mv, aien-sovereign-core-mv), protocols (aien-protocols-mv) |
| Programme close guard and source-control guard | Model weights and model generations (recorded by digest only) |

Moving coordination here does not mint a second identity and does not fork memory or authority. Component owners stay where they are; this repository links to them.

## Layout

- `docs/MISSION.md`: Allen's mission and endpoint, in Drake's words.
- `docs/PHASES.md`: the phase ledger P0 to P7 with issue links and status.
- `docs/PLAN.md`: P0 work streams, directories, branches.
- `docs/SOURCE_MAP.md`: where every existing Allen part lives today, with pinned commits (stream `map`).
- `inventory/`: conversation log inventory and access-controlled source manifest (stream `inventory`). Counts and dates only.
- `docs/B0_ACCEPTANCE_CONTRACT.md`: the first bounded task, gates, budgets, access rules, devices (stream `contract`).
- `guard/`: Rust crate `allen-guard`: programme close guard and source-control guard (stream `guards`).
- `evidence/`: test logs and run receipts, one directory per stream.

## Visibility

Created private on 2026-10-20 as issue aien-architecture-mv#279 asked. Decision recorded in `docs/PLAN.md`: the repository becomes public when the source-control guard is green on `main` (it is the thing that makes public safe), as every other aien-dev repository is public. Raw logs, personal training artifacts and weights stay access controlled whatever the repository visibility.

## License

AGPL-3.0-or-later. AIEN is non-commercial.

## How I bound Allen's first evaluation

I keep Allen's [mission](docs/MISSION.md) and [phase ledger](docs/PHASES.md) separate from the identity object, Cortex memory and runtime authority they describe. [The P0 plan](docs/PLAN.md) assigns `SOURCE_MAP.md`, B0 acceptance, inventory and guards to separate streams; on `main` at `e97222e`, those files and a runnable evaluator are **absent**. A checkpoint would be a model generation, not Allen's identity. The phase table says P0 ACTIVE and P1–P7 PROPOSED, with qualification NOT_RUN. This is the present boundary, not a completed training or release flow.

### Synthetic status check

At commit `e97222e`, with Python 3 and no personal data or model, run:

```sh
python3 - <<'PYCODE'
from pathlib import Path
p=Path('docs/PHASES.md').read_text()
assert '| P0 |' in p and 'ACTIVE' in p and 'NOT_RUN' in p
missing=[x for x in ('docs/SOURCE_MAP.md','docs/B0_ACCEPTANCE_CONTRACT.md','guard/Cargo.toml') if not Path(x).exists()]
print('P0 status: ACTIVE / NOT_RUN')
print('evaluation unavailable:', ', '.join(missing))
PYCODE
```

Expected exit 0 and the missing-file list. This checks the published contract boundary only. This main-only check does not evaluate a guard. The existing pending guard branch supplies the actual offline verdict exercise below; it is not merged or a B0 qualification. No raw conversations, weights or access changes are needed. [Replay receipt](docs/teaching-replay.txt).


### Parent fresh-checkout replay

A separate coordination replay is retained in [the parent receipt](docs/parent-replay-2026-10-22.txt). Its scope and observed exit are explicit; source review and final desk qualification remain separate. A recorded absence or expected failing baseline is not a passing implementation.


### Existing pending guard: accepted and refused synthetic snapshots

The existing [`guards/v0` implementation at `ec97384701c6e86aa2be745c1336b70645a549d4`](https://github.com/aien-dev/allen/tree/ec97384701c6e86aa2be745c1336b70645a549d4) is separate from this documentation and was not on main at the inspected pin. It provides a real offline programme-close predicate, not a trained model or identity migration.

Trace the path from [`main.rs::close_check`](https://github.com/aien-dev/allen/blob/ec97384701c6e86aa2be745c1336b70645a549d4/guard/src/main.rs) through [`Policy`](https://github.com/aien-dev/allen/blob/ec97384701c6e86aa2be745c1336b70645a549d4/guard/src/policy.rs) and [`close::evaluate`](https://github.com/aien-dev/allen/blob/ec97384701c6e86aa2be745c1336b70645a549d4/guard/src/close.rs): policy names required issue identities; a saved synthetic issue snapshot supplies their state and body; the evaluator produces a verdict and blockers; the CLI maps accepted to exit0 and rejected to exit2. The fully accepted fixture is the positive case; the all-open fixture is a meaningful refusal control. Neither calls `--live` or edits GitHub.

Prerequisites: GitHub read access to this private repository, Git, Rust/Cargo (replayed with the version in the linked raw receipt), Python3, and Cargo dependency access/cache. In a new directory:

```sh
set -eu
git init allen-guard-lesson
cd allen-guard-lesson
git remote add origin https://github.com/aien-dev/allen.git
git fetch --depth 1 origin ec97384701c6e86aa2be745c1336b70645a549d4
git checkout --detach FETCH_HEAD
cargo test --locked
cargo run --quiet --locked -- close-check --policy guard/policy.toml \
  --snapshot guard/tests/fixtures/close/fully-accepted.json > accepted.json
rc=0
cargo run --quiet --locked -- close-check --policy guard/policy.toml \
  --snapshot guard/tests/fixtures/close/all-open.json > refused.json 2> refused.md || rc=$?
test "$rc" -eq 2
python3 - <<'PYCODE'
import json
accepted = json.load(open('accepted.json'))
refused = json.load(open('refused.json'))
assert accepted['accepted'] is True and refused['accepted'] is False
print('accepted_fixture=true; all_open_fixture=false; refusal_exit=2')
PYCODE
```

Expected: the existing41 tests pass, the first verdict accepts, the second refuses with exit2, and the final assertion exits0. [Actual parent replay](docs/pending-guard-replay.txt) retains the test output and Rust version. This qualifies only offline synthetic policy evaluation at that pending source pin. It does not qualify live issue-event enforcement, hook installation elsewhere, model evaluation, training, memory continuity, phase completion or Allen B0. The phase status and private-repository boundaries above remain unchanged.
