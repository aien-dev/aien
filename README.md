# Allen

Allen is the persistent subject that the AIEN system aims to sustain: one identity across the iMac, the Raspberry Pi, the DGX Spark and the MacBook (architecture ADR 0035). This repository is Allen's project home: mission, phase ledger (P0 to P7) and a plan for data contracts, evaluation harness, release manifests and the acceptance contract for the first qualified release, **Allen B0**.

**Pre-alpha.** Nothing here is qualified. Every claim in this repository links to a file under `evidence/` or to a receipt in [aien-dev/aien-receipts](https://github.com/aien-dev/aien-receipts); a sentence with no link is a plan, not a result.

## What lives here and what does not

| Here | Not here (owner) |
|---|---|
| Mission, phase issues P0 to P7; B0 acceptance contract planned | Allen's identity object, SubjectState kind 24 (aienos-mv, ADR 0018) |
| Conversation log inventory planned: counts, dates, hosts, gaps | The logs themselves (Spark `~/archive/agent-chats/`, access controlled) |
| Data contracts and synthetic fixtures planned | Raw conversations, trained weights, secrets (never in any repository) |
| Evaluation harness and release manifests planned (digests, pins) | Memory (Cortex, ADR 0022), runtime authority (aegis-runtime-mv, aien-sovereign-core-mv), protocols (aien-protocols-mv) |
| Programme close guard and source-control guard planned, not present on `main` | Model weights and model generations (recorded by digest only) |
Moving coordination here does not mint a second identity and does not fork memory or authority. Component owners stay where they are; this repository links to them.

## Layout

- `docs/MISSION.md`: Allen's mission and endpoint, in Drake's words.
- `docs/PHASES.md`: the phase ledger P0 to P7 with issue links and status.
- `docs/PLAN.md`: P0 work streams, directories, branches.
- `docs/SOURCE_MAP.md`: planned source map with pinned commits (stream `map`); not on `main`.
- `inventory/`: planned conversation log inventory and access-controlled source manifest (stream `inventory`); currently only `.gitkeep`.
- `docs/B0_ACCEPTANCE_CONTRACT.md`: planned bounded task and gates (stream `contract`); not on `main`.
- `guard/`: planned Rust `allen-guard` programme close and source-control guards (stream `guards`); currently only `.gitkeep`, with no crate or policy on `main`.
- `evidence/`: reserved for test logs and run receipts, one directory per stream; currently only `.gitkeep`.

## Visibility

Created private on 2026-10-20 as issue aien-architecture-mv#279 asked. `docs/PLAN.md` proposed making the repository public after a green source-control guard on `main`. This repository is now publicly readable, but no guard or green guard receipt exists in this `main` tree; public visibility is not evidence that the planned safeguard ran. Raw logs, personal training artifacts and weights remain access controlled regardless of visibility.

## License

AGPL-3.0-or-later. AIEN is non-commercial.

## Human-Directed Agentic Engineering

Development follows Human-Directed Agentic Engineering (HDAE): humans define goals,
architecture, constraints, acceptance criteria, and stopping points; agents implement,
execute checks, diagnose failures, and revise within those boundaries. Human review
retains responsibility for claims, acceptance, and release decisions. This describes
the development method, not a change to runtime autonomy or historical evidence.

For the documented method and a systems-software case study, see Gregory M. Kurtzer
(2026), *Ginux: Building an Independent Kernel That Runs Linux Userspace through
Human-Directed Agentic Engineering*, technical report, v1, Zenodo,
<https://doi.org/10.5281/zenodo.23682548>.
