# Allen ownership rules (P0, stream `map`)

Status: PROPOSED. Qualification: NOT_RUN. Companion to `docs/SOURCE_MAP.md`, which gives the paths and pinned commits behind every row.

## The rule

Moving Allen's coordination to `aien-dev/allen` does not mint a second identity, does not fork memory and does not create a new authority.

In so many words:

- There is one Allen identity. It is the AIENOS `LogicalAgentId` and its AgentRoot, carried by the SubjectState object (continuity kind 24). This repository holds no identity, no `AllenId`, no copy of the subject chain.
- There is one memory lineage per Allen. Cortex owns memory (ADR 0022). This repository holds no memory store and never receives raw conversation text.
- There is one authority path. Permission comes from the approval desk and the AIENOS capability authority, through an INTERPLANE `RuntimeAuthority`. This repository decides, grants and executes nothing.
- A model checkpoint is not Allen. Model generation ids are recorded beside Allen's identity, never as it.

## Objects that must have exactly one writer

| Object | The one writer | Everyone else |
|---|---|---|
| SubjectState chain (kind 24), AgentRoot, manifest | the AIENOS kernel, inside the identity provisioning transaction and a committed successor (ADR 0035 invariants I6, I8) | read through the resolver; a fork, gap or foreign root is CORRUPT and stops |
| Genesis of a subject | the AIENOS kernel, once per installation (`cs_provision`) | nobody creates it from a host tool, a test script or this repository |
| Cortex journal | omega `rx_cortex`, one writer per journal (ADR 0022, `cx_claim_writer` and file lock) | recall only; model output enters as candidates and becomes fact only through `cx_promote` with an evidence object |
| Identity-to-memory binding (lineage digest of journal record 1) | the Allen binding record (omega `allen_bind`, host pin in `aien-allen`) | a subject acts only with the journal it names; anything else is refused before publication |
| Persona profile revision chain | the `aien-allen-profile` crate (sovereign-core) | read only; the profile is not identity and never grants permission |
| Scoped Allen memory store | the `aien-allen-memory` crate (sovereign-core) | through `aien allen memory ...`; see the open reconciliation below |
| Approval and capability decisions | the approval desk (S4 `authorize`) and the AIENOS capability authority, the only mint | requesters ask; they do not decide |
| Conversation archive `records/` and `raw/` | `agent-archive collect` on the Spark | derived views read it; none write to it |
| Deployment (model swap) record | `aien-allen::deployment` (sovereign-core), host produced | model-supplied identity never enters it |
| Receipts in `aien-receipts` | the Spark pipeline (signs `aien-verification-bundle/1`) | cite by repo and sha |

## Who owns what

| Area | Owner | Basis | What `aien-dev/allen` does |
|---|---|---|---|
| ALLEN identity and SubjectState | aienos (`aien-dev/aienos-mv`), with architecture | ADR 0035; aienos ADR 0018 (header still Proposed, format not frozen) | links; acceptance tests only |
| Binding record and standing-intent publication | omega (`aien-dev/omega-mv`) | ADR 0035; `spec/allen.md` | links |
| Cortex | omega `rx_cortex` | ADR 0022 (accepted); `cortex-rs` is non-authoritative and to be retired; archived repository `aien-dev/cortex-rs` | never writes; never adds a caller to `cortex-rs` |
| Host identity gate, persona profile, scoped memory, `aien` CLI, chat loop, compose and approval desk, model server | sovereign-core (`aien-dev/aien-sovereign-core-mv`) | ADR 0035, 0036; architecture#159, #267, #269 | consumes through the CLI and crates |
| Runtime authority, delegated work, delivery and cron | sovereign-core (production path), aegis-runtime (`aien-dev/aegis-runtime-mv`, pre-alpha, outside the v1 E2E release), INTERPLANE (`aien-dev/interplane-mv`, the boundary) | AEGIS README; INTERPLANE README ("Models express intent. Runtimes retain authority.") | links |
| Protocols and wire formats | aien-protocols (`aien-dev/aien-protocols-mv`) | PST1 draft (#27, #28), TRN1, evidence receipt | any new Allen message is proposed there, not defined here |
| Conversation archive | agent-archive (`aien-dev/agent-archive`) and the Spark folder `~/archive/agent-chats/` | its README; PLAN.md decision 2 | holds pointers, counts and digests only |
| Site and presence | aienos.com (`aien-dev/aienos.com`) and `aien-dev/.github` | `aien-voice` rules | links; no private content |
| Device code (iMac kernel window, Pi, Spark native boot, phone/MacBook client) | aienos, per-issue owners (#396, #398, #399); local client unowned today (see `SOURCE_MAP.md` M5) | the programme gate in `aien-dev/allen#1` | acceptance tests for P6 |
| Release authority for the whole system | architecture issue #190 | `aien-dev/allen#1` ("preserve #190's release authority") | produces release manifests as input; does not release |
| Evaluator-only material | `aien-dev/aien-sealed` (private) | repository map | never imports it into a candidate under test |

## What `aien-dev/allen` owns

- the programme: mission, phase ledger (P0 to P7, then B0), `docs/PHASES.md` and `docs/PLAN.md`;
- data contracts for episodes, labels and evaluation records, as schemas and synthetic fixtures;
- the evaluation harness and its isolation rules (held-out data stored apart before any fitting, indexing or preference extraction);
- release manifests: which model, memory, runtime and dataset identities make up a candidate, recorded separately from Allen's identity;
- guards: the programme close guard and the source-control guard that refuses raw logs, weights and secrets;
- the B0 acceptance contract, budgets, access rules, and the deletion and export ownership record.

## What it must not own

- an identity, an id scheme or a copy of a subject chain;
- a memory store, an index of conversation text, or embeddings of it;
- a loop, a scheduler or a daemon (ADR 0035 invariant I7);
- permission decisions or capability minting;
- a protocol format that an existing protocol crate could carry;
- weights, raw conversations, credentials or private training samples, in any branch, issue, pull request or CI log.

## Open ownership questions (recorded, not decided here)

1. **Memory layering.** `rx_cortex`, `aien-allen-memory`, the iMac `AIENALM1` store and the anchor fact store (PR #417) all exist or are proposed. ADR 0036 leaves open whether the Omega-layer owner and `aien-allen-memory` merge or stay layered. Until an architecture ADR decides, `allen` writes to none of them and P1 episodes point into the archive, not into a store.
2. **Multi-device writers.** ADR 0035 allows one subject chain per AgentRoot. Four devices need a reconciliation design before P6; it is an aienos and architecture decision (`SOURCE_MAP.md` M1).
3. **Standing intent beyond `GOAL_LATENCY`.** Needs an aienos ADR 0018 amendment (`SOURCE_MAP.md` M2). Host goal records exist meanwhile and are not subject intents.
4. **Deletion and export.** The B0 contract stream records who deletes and exports a person's data; the stores that must honour it are listed above, and `aien-allen-memory` states that `forget` makes an item unreadable in its own store only (`RETENTION.md`).
5. **Who may change this page.** The `map` stream wrote it. A change that moves a row between owners needs the named owner's agreement in the pull request, and an architecture ADR when it changes an accepted ADR.
