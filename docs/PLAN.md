# P0 plan: streams, directories, branches

Issue: Allen P0 (see `docs/PHASES.md` for the number in this repository; formerly aien-architecture-mv#279). Programme: formerly aien-architecture-mv#278.

| Stream | Directory it owns | Branch | Delivers | Ledger |
|---|---|---|---|---|
| `map` | `docs/SOURCE_MAP.md`, `docs/OWNERS.md` | `map/v0` | Where every existing Allen part lives (SubjectState, Cortex, agent-archive, runtime, protocols, device code), with pinned commits; extend/reuse/missing per part; ownership and import boundaries | see ledger |
| `inventory` | `inventory/` | `inventory/v0` | Conversation log inventory (agents, hosts, date spans, counts, raw mirror coverage, tool evidence, gaps) and the access-controlled source manifest pointer. Counts and dates only, never content | see ledger |
| `contract` | `docs/B0_ACCEPTANCE_CONTRACT.md`, `docs/PHASES.md` (status column) | `contract/v0` | The first bounded task frozen (project preparation with constraints, correction, restart, verified output), measurable human-effort and outcome gates, budgets, access rules, role and permission boundary, supported devices, deletion and export ownership | see ledger |
| `guards` | `guard/`, `Cargo.toml`, `.github/workflows/`, `.gitignore`, `scripts/`, `docs/CLOSE_CHECKLIST.md` | `guards/v0` | Rust crate `allen-guard`: (1) programme close guard, reopens the tracker when a phase or prerequisite is open or its checklist is incomplete, tested on open / closed-with-missing-evidence / fully-accepted fixtures; (2) source-control guard, refuses raw logs, weights and secrets, tested on synthetic fixtures; CI workflows green | see ledger |
| `desk` | merges | `main` | Merge the four streams, flip visibility when the source-control guard is green on main, close P0 against its acceptance list | see ledger |

The coordinator owns `README.md`, `AGENTS.md`, `docs/MISSION.md`, `docs/PLAN.md` and the issue transfer.

## Decisions recorded at P0

1. **Visibility.** Private at creation (as #279 asked). Becomes public when the source-control guard workflow is green on `main` and the inventory has been read once to confirm it holds counts and paths, not content. Reason: every other aien-dev repository is public and AIEN builds in the open; the guard is the physical reason public is safe.
2. **Raw data location.** The archive stays on the Spark at `~/archive/agent-chats/` (aien-dev/agent-archive). This repository holds pointers, counts and digests. Deletion and export ownership is recorded in `docs/B0_ACCEPTANCE_CONTRACT.md`.
3. **No new identity.** ALLEN identity, SubjectState, Cortex lineage and runtime authority keep their owners (ADR 0035, ADR 0022). Anything here that needs them imports or links; it never copies.
