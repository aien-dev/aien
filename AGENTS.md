# Instructions for agents working in aien-dev/allen

Read before any edit, in this order:

1. `docs/MISSION.md` and `docs/PHASES.md` (what Allen is for and where things stand).
2. `docs/B0_ACCEPTANCE_CONTRACT.md` (what counts as done for the first release).
3. aien-architecture-mv: `PLAN_AUTHORITY.md`, `CURRENT_EXECUTION_PLAN.md`, accepted ADR 0035 (Allen boundary), ADR 0022 (Cortex owner), ADR 0024 (Rust scaffolding, Omega destination).
4. `docs/SOURCE_MAP.md`: the owners of every existing part. Reuse or extend them; never create a parallel identity, memory store or authority here.

Rules:

- My stack only: Rust now, Omega as destination. No Python, no C++, no CUDA, no third-party inference engine. Outside tools are yardsticks or test oracles, never shipped.
- Raw conversations, credentials, weights and private training samples never enter this repository, in any branch, issue, PR or CI log. Publish synthetic fixtures and access-controlled references (host, path, digest, count). The source-control guard (`guard/`) enforces what it can; you enforce the rest.
- Drake's words are preserved as written, including profanity. Style or frustration is never turned into a claim about feelings, permission or correctness.
- Every number names its source: a file under `evidence/`, a receipt, or the arithmetic. No estimates without evidence.
- Status words are separate from verdicts: progress is PROPOSED, SCOPED, ACTIVE, IN_REVIEW, COMPLETE; qualification is PASS, FAIL, INCONCLUSIVE, NOT_RUN. A closed issue with waived or NOT_RUN criteria is not complete; the programme close guard reopens it.
- Phase numbers (P0 to P7) are sequence, not priority. Model generation ids are recorded separately from Allen's identity; a checkpoint is not Allen.
- One owner per directory; see `docs/PLAN.md`. Push branches and write a READY line for the PR desk; do not open or merge pull requests yourself.
- Git identity for commits made on Drake's behalf: Drake Stapleton <drake@aienos.com>.
