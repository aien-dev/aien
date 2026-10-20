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
