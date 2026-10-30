# Goal to typed microjobs (Allen #13)

Allen keeps one persistent objective as a typed, dependency-bound microjob DAG plus an append-only event journal. The seeded `.om` kernel `src/goal_microjobs/kernel.om` is the only admission logic: it replays plan + journal from stdin and either prints the derived state or refuses with a code. It runs no job, calls no model, and writes no memory or authority state. The model or planner proposes; the kernel decides what is admitted.

Status: **IMPLEMENTED, HOST_TESTED (offline, synthetic fixtures)**. The bounded canonical Aienet-0 adapter below is also HOST_TESTED. Not run: model inference, Cortex write/restart, general multi-node canonical export, routing comparison, GPU or physical qualification. Deployment OFF.

## Boundary

| Here (Allen) | Owner elsewhere |
|---|---|
| Objective plan records, journal replay, admission refusals, derived node state, objective receipt line | Execution of a node: Omega scheduler / FORGE placement; worker admission: Core #735 |
| Retry, budget, cancellation, correction and effect-once rules over the journal | Canonical wire ABI: aien-protocols-mv#50 (`specs/microjob/SPEC.md`, MJB1/MJR1 draft) |
| Local journal file in an owner-private directory (mode 700) | Durable memory: Omega Cortex (ADR 0022); the Cortex writer adapter does not exist yet |

The journal is not Cortex and is not a second memory store: it is the local replay log of one objective until the Cortex owner publishes a typed writer. Shell (`scripts/goal_microjobs/microjobs.sh`) only handles files, the `flock` lock and the atomic rename, because the seeded language has no file or argument API.

## Records (local replay ABI; canonical adapter below)

Whitespace-separated decimal words, one record per line. A 32-byte SHA-256 digest is written as four big-endian 64-bit words (`microjobs.sh digest TEXT`).

Header: `1 abi objective(4) owner runtime effect_ceiling node_count terminal max_attempts max_model_calls max_tokens budget_in budget_out budget_time_ms`

Node (ids 1..N in order): `2 id kind op route profile effect in_tok out_tok req_in req_out verifier_kind verifier retry_class max_attempts tenant time_ms required operand(4) ndeps deps...`

Event: `3 seq type node attempt generation issuer verdict digest(4) tokens time_ms`

| Event type | Admitted when | Effect |
|---|---|---|
| 1 DISPATCH | node pending, all dependencies done, current generation, attempt = previous + 1, issuer is a worker (not owner, runtime or the node verifier), attempts and model-call and token reservations within budget | running; reserves `in_tok + out_tok` for a NEURAL node |
| 2 RESULT | running, same attempt and generation, same worker, digest not zero, tokens and time within the node contract, COMPUTE spends zero tokens | resulted (awaiting verification) |
| 3 VERIFY | resulted, issuer is the node verifier and not the worker, digest equals the result | verdict 1: done; verdict 0: retry or failed |
| 4 FAIL | running, issuer is the worker or the runtime (orphaned lease after a restart) | retry while attempts remain, else failed |
| 5 CANCEL | issuer is the owner; node 0 cancels the objective | node and every transitive dependent not done become cancelled |
| 6 CORRECT | issuer is the owner, names the current generation, new operand digest differs | node and every transitive dependent: generation + 1, reset to pending |
| 7 REFUSE | the running worker abstains, or the runtime refuses a pending node | refused (terminal for that generation) |
| 8 EFFECT | issuer is the runtime, node done with effect class 2, current generation, idempotency key not zero | effect committed once per generation |

Output: `100 status nodes done attempts model_calls tokens_reserved last_seq time_ms cancelled tokens_used`, one `101 id state generation attempts blocked ready effect_generation` per node, `102 ready-ids...`, and when complete `103 objective(4) terminal_result(4) terminal_generation last_seq`. Objective status: 1 active, 2 complete, 3 failed, 4 cancelled, 5 blocked, 6 stalled (nothing running or fundable). Node state: 1 pending, 2 running, 3 resulted, 4 done, 5 failed, 6 cancelled, 7 refused. Complete means every required node done, the terminal node verified and every required effect committed at its current generation.

Refusal codes (`199 seq code`, exit = code): 2 truncated, 3 malformed or too large, 4 read error, 5 wrong record tag, 10 ABI version, 11 node count, 12 node id order, 13 enum, 14 token profile, 15 needs expansion, 16 no verifier, 17 cross tenant, 18 unauthorized effect, 19 missing or duplicate dependency, 20 cycle, 21 terminal invalid or optional, 22 missing operand, 23 retry class, 24 zero cap, 25 no objective/owner/runtime, 26 over budget, 30 sequence, 31 unknown node, 32 unknown event, 33 wrong state, 34 stale generation, 35 wrong attempt, 36 attempts exhausted, 37 model-call budget, 38 token budget, 39 unauthorized issuer, 40 self-verification, 41 digest, 42 over node contract, 43 dependency not done, 44 effect not allowed, 45 duplicate effect, 46 correction without change, 47 objective cancelled, 48 tokens on COMPUTE, 49 verdict.

### Alignment with the MJB1 draft

Checked against `specs/microjob/SPEC.md` draft v0.1 on aien-protocols-mv main `e705fdc9c97394f17f32f1dcbcbf038ca556250b`. Same closed values: kind (1 COMPUTE, 2 NEURAL), op ranges per kind, profile 0..4 with caps 64/16, 128/32, 256/64, 512/128, effect class 0/1/2 bounded by the header ceiling, verifier kind 1..3, retry class 1..3, max attempts 1..8. Same rules: COMPUTE spends zero tokens; required tokens above caps refuse as needs-expansion (no silent truncation); NEVER with more than one attempt and EFFECT with IDEMPOTENT refuse; sums of node input-token, output-token and time caps stay within header budgets; node tenant equals the objective tenant; dependency cycle refuses. The local replay kernel and canonical document serve different roles. Its original admission and event semantics are unchanged.

Allen-local records intentionally retain integer authority roles, routes, required/terminal markers and journal sequence numbers. Canonical documents use explicit external references and are re-issued for each generation. `canon.om` supports only the bounded one-node COMPUTE/MATMUL Aienet-0 shape, not arbitrary local DAG export. Cryptographic MJR1 and AN0V verification remains with the protocols/Open Humanity checker, not the replay kernel.

## Restart, partial completion and duplicates

Every `propose` takes the lock, copies the journal to `journal.cand`, appends one event, replays plan + candidate through the kernel, and only on exit 0 runs `sync` and renames the candidate over the journal. A writer killed before the rename leaves the journal unchanged; a restarted process replays the same bytes to the same state. A running lease left by a stopped process is closed by a runtime FAIL and retried as a new attempt; the late result of the old attempt and any repeated result or effect are refused.

## Reproduce

```sh
OMEGA_WORKTREE=<seeded Omega worktree at c434565c> bash tests/goal_microjobs/gate.sh
```

`scripts/goal_microjobs/build.sh` checks the same Omega commit and compiler pins as Allen #12's harness gate. The gate writes `evidence/goal-microjobs/offline-*/` (unsigned receipt, transcript, final status and journal, mutation table).

The historical compiler is **not tracked at that Omega revision**. A fresh
clone without archived `build/L574/toolchain` artifacts returns exit 3 with
`BLOCKED`, rather than an unexplained checksum failure. Supply that archive
under the pinned checkout before running the gate. Required archive identities:
`build/bootstrap/omc` SHA-256
`191b776ef98821597c3e30655da6d680a9b66edbc9ceaca3c39c61ea6df098e9`;
`seed/omc/omc.om` SHA-256
`8608fa11f6a2cf1c50db22d871eef16b00d5bc719bc1a222cc3e456984ac5ebf`.
The archive also contains `tools/verify-elf.sh`. No download or compiler
substitution is implicit. Without this prerequisite the replay is BLOCKED,
not PASS. PR #14 delivers the admission/replay kernel only; the open #13
items below remain a separate workstream.

The 12-node acceptance objective runs nodes 1 to 4 concurrently before the join at node 7; it has five COMPUTE nodes with zero tokens before the correction, three bounded NEURAL routes, one refused optional teacher route, one model failure with retry, one interrupted lease after a SIGKILL'd writer, one rejected model answer with retry, and one owner correction of node 3 that resets exactly nodes 3, 7, 8, 9, 10, 11, 12. Expected totals, recomputed with the Wolfram Language evaluator: tokens reserved (60+12) + 2(120+30) + 4(120+30) = 972; tokens used 50+40+110+120+118+116 = 554; time 12531 ms; 18 attempts; 7 model calls; static caps 800 input, 192 output, 18800 ms against budgets 1000, 256 and 20000.

## Open

- General canonical multi-node export, neural jobs and non-COMPLETED canonical outcomes are outside the bounded Aienet-0 adapter.
- Cortex writer and restart through the Omega owner; Core #735 worker admission and dispatch; qualified-worker registry for route selection.
- Objective text to DAG rule baseline and shadow route policy; ordinary routing vs microjob comparison; native `.om` plan export.

## Canonical Aienet-0 adapter (M1)

`src/goal_microjobs/canon.om` is IMPLEMENTED and HOST_TESTED against protocols
`e705fdc9c97394f17f32f1dcbcbf038ca556250b`. It emits canonical MJB1 bytes,
hashes them in Omega, and checks receipt/countersign bindings before formatting
local RESULT and VERIFY events. It does not verify P-256 signatures, execute a
worker, authenticate integer authority roles, append a journal, or grant authority.
The caller MUST successfully run `aienet0-run check` against its pinned executor
and independent verifier keys before ingest, and replay/atomically commit the
events through the kernel. Passing ingest alone is not authenticated completion.
**Ingest is not a standalone verifier. It must only receive the exact immutable
document/MJR1/AN0V bytes that passed that Rust check.** In particular, ingest
does not verify either signature, source/model/policy hashes, fuel/memory/work
accounting or the recompute verdict's cryptographic derivation. Refreshing an
AN0V receipt hash is not signature verification. A changed AN0V signature can
still pass ingest; it must fail the preceding Rust checker.

### Build and pins

```sh
OMEGA_OMC=/path/to/omc OMEGA_MV=/path/to/omega-checkout \
  sh scripts/goal_microjobs/canon-build.sh /tmp/canon
```

The compiler is Omega `e5b32567`, SHA-256
`2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f`.
The build extracts `55845e70:om/sha256/sha256-om2.om` from that checkout and
requires SHA-256 `dbf002dd6aa36585632b9d01d98ac3f0bd2fa0f0475082940de53638847994bb`.
Only the four `export fn` prefixes are removed for program mode, following the
protocols jobpath build convention. Missing artifacts or mismatches exit 3 with
BLOCKED; they never invoke a fallback compiler. The shell script is a migration
build adapter under [shell retirement #22](https://github.com/aien-dev/aien/issues/22),
not a first-party runtime implementation.

### Emit

`/tmp/canon emit < records > emission` consumes exactly these four whitespace
decimal records (all digest groups are four big-endian u64 words):

1. The existing 17-word header record, including tag 1.
2. One 23-word node record, including tag 2 and `ndeps=0`.
3. That node's kernel status record:
   `101 id state generation attempts blocked ready effect_generation`.
4. The explicit binding record:
   `4 objective(4) tenant(4) subject(4) approval(4) capability(4) expires_at m k n seed incarnation`.

Every reference group and expiry must be nonzero; binding objective must equal
the header objective. The caller supplies the actual Aienet-0 `tenant()` and
`capability()` values and the submitter's `approval_ref`, never integer stand-ins.
Dimensions are 1 through 256; seed is u64; incarnation and generation are
nonzero u32; node id is nonzero u16. The 15-byte payload is kind 1, m/k/n u16 BE,
then seed u64 BE. Its SHA-256 must equal the node operand digest. A correction
uses the kernel's corrected operand and derived generation, not the original
plan's stale operand. Node shape is COMPUTE/MATMUL, route 0, profile ZERO,
effect COMPUTE, zero token caps and requirements, RECOMPUTE, NEVER/one attempt,
no dependencies, and a nonzero local verifier.

Output framing is `document[640] || payload[15] || dag_digest[32]`, all binary:

```sh
dd if=emission of=document bs=1 count=640 status=none
dd if=emission of=payload bs=1 skip=640 count=15 status=none
dd if=emission of=dag_digest bs=1 skip=655 count=32 status=none
```

The one-node document uses the supplied refs, incarnation and expiry. Node and
operand generations both equal the derived status generation. RECOMPUTE has
zero verifier_ref and pure=1; cancel DISCARD, CPU substrate, exact precision,
DIGEST rank-zero result; unused and reserved bytes are zero. Time cap comes
from the local node. Fuel/work are `m*k*n`; memory is `4*(m*k+k*n+m*n)`, following
the protocols profile. Header budgets equal the single node's caps.

Job identity is the first 16 bytes of
`SHA-256("AIEN-ALLEN-AN0-JOB-V1\0" || objective[32] || node_id_u16_BE || generation_u32_BE)`;
idempotence uses `"AIEN-ALLEN-AN0-IDEM-V1\0"` with the same suffix.
NUL is a literal zero byte. Changing generation changes both identities and
the document/dag digest, not the authority references.

### Ingest

`/tmp/canon ingest < ingest-input > events` consumes:
`document[640] || MJR1[404] || AN0V[236] || expected_ascii`, where the final
ASCII record is:

`5 node generation attempt worker verifier executor_key_sha256(4) verifier_key_sha256(4) next_sequence objective_id(4) effective_operand_digest(4)`

This is exactly 23 decimal words. The original first 15 words are unchanged;
objective occupies zero-based words 15..18 and effective operand 19..22.
The caller MUST derive those pins from its trusted objective header and replayed
effective operand (including the latest CORRECT), never from the supplied
document or receipt. A different objective or operand must not complete the
original task even when its bundle and signatures are otherwise valid.

The key digests are SHA-256 of the 33-byte compressed SEC1 public keys, not keys
or signatures. Worker/verifier are the caller's pinned local role integers,
nonzero and distinct. The adapter checks document objective and CONTENT operand
digest against those independent pins, then derives job/idempotence identities
from the expected objective and node. It requires the receipt's full 32-byte
job/idempotence pair, generation, attempt (one), COMPLETED outcome, dag digest,
nonzero output, zero COMPUTE tokens and bounded time. It checks all MJR1 reserved
bytes are zero and recomputes input_binding as
`SHA-256("MJR1-BIND" || operand_kind_u8 || operand_generation_u32_BE || operand_digest)`,
following SPEC section 5.1 for one operand and no dependencies.
It checks AN0V framing, hash of the entire 404-byte receipt (including signature),
cross-record dag/output/verdict equality, and both public-key hashes.

On success exactly two lines are emitted:
`3 seq 2 node attempt generation worker 0 output(4) 0 used_time_ms`, then
`3 seq+1 3 node attempt generation verifier 1 output(4) 0 0`.
MJR1 used_time_ms is decoded at offset 76 and output at 144. No event is
printed for any input mismatch. Duplicate completion and stale replay are
ultimately refused by the existing kernel, not by pretending ingest owns a
durable ledger. The caller must atomically append both lines, or after a crash
compare an already appended RESULT byte-for-byte and append only its matching
VERIFY. Never re-dispatch or replace an existing completion on recovery.

Refusals print `CANON_<NAME>` to stderr and exit: 2 INPUT (including truncation),
3 IO, 10 REF, 11 PAYLOAD, 12 SHAPE, 13 RANGE, 14 GENERATION, 15 JOB,
16 OUTCOME, 17 DAG, 18 OUTPUT, 19 AN0V, 20 KEYPIN, 21 ATTEMPT, 22 RESOURCE,
23 OBJECTIVE, 24 OPERAND, 25 BINDING, 26 RESERVED.
No refusal writes event/document bytes to stdout.

### Host acceptance and limits

```sh
taskset -c 10-14 nice -n 19 ionice -c3 env \
  OMEGA_OMC=/path/to/pinned/omc OMEGA_MV=/path/to/omega-checkout \
  OMEGA_WORKTREE=/path/to/archived/c434565c \
  CANON_RUN_ROOT=/tmp/canon-results bash tests/goal_microjobs/canon/run.sh
```

Prerequisites: AArch64 Linux, the two pinned compilers above and the existing
kernel compiler archive described under Reproduce, bash, coreutils, git, sed,
xxd. The committed synthetic hex fixtures were generated with an external
throwaway Rust oracle using protocols `e705fdc9`, `p256 0.14.0` and `sha2 0.10.9`.
The positive receipt/countersign use deterministic synthetic test keys; these
are not credentials or hardware receipts. The external Rust check compared
the complete Omega document to independent Rust `encode`, verified `decode`
and `dag_digest`, `seal_bundle`/`admit_bundle`, `executor_receipt`/`check_receipt`,
`countersign`/`check_countersign`, exact event bytes, and generation-two admission.
The throwaway helper is not shipped. Fresh clones can replay the committed
byte-level oracles without Cargo or generated helper source.

The gate checks exact emission and events, nineteen refusal fixtures and sixteen
source mutants, replay through the archived kernel to DONE, and compiler
pin refusal. Guard-isolating malformed fixtures deliberately refresh AN0V
bindings without signatures where necessary: they test individual structural
guards, not authenticated network acceptance. `staleoutput` leaves signatures
and AN0V stale and is also rejected by the external Rust receipt checker.
The mutant table records that each guardless binary accepts its targeted
malformed input while the real adapter refuses with the named code.
The new objective/operand swap fixtures carry valid independently admitted,
executed, signed and countersigned jobs; they are refused only because the
caller's expected task differs. The objective-pin mutant removes both the
explicit equality check and expected-objective identity derivation. The
idempotence-only fixture kills the specific mutant shortening the comparison
from 32 to 16 bytes. Three reserved-byte-region fixtures share one guard mutant.

WolframLanguageEvaluator: `FromDigits[ToCharacterCode["MJB1"],256]`,
`FromDigits[ToCharacterCode["MJR1"],256]`,
`FromDigits[ToCharacterCode["AN0V"],256]` returned 1296712241, 1296716337,
1095643222. Query `3*2*2` and `4*(2*3+3*2+2*2)` returned fixture caps 12 and
64 bytes. Bounded-dimension maxima queries returned work 16777216 and memory
786432 bytes, both representable in the encoded u64 cap fields.
These are computed bounds, not measured performance.

HOST_TESTED is not hardware qualification. P1 two-machine, P2 federation,
GPU, deployment and merge are NOT_RUN. General DAG conversion and P-256
verification in Omega are not claimed.

### M1 loopback execution and interruption acceptance

`tests/goal_microjobs/aienet-m1/sequence.sh` is a shell migration adapter
under [aien#22](https://github.com/aien-dev/aien/issues/22), not a new
admission or signature implementation. It reads the current generation from
kernel status and routes the kernel-validated journal through `recovery.om`
to derive the effective operand, then calls `canon emit`, persists the unchanged
signed bundle before DISPATCH, resends with the worker's durable `--retry`
state, checks signatures and independent recomputation through Open Humanity,
then calls `canon ingest` and proposes RESULT and VERIFY through the kernel.
`recovery.om` compares every field of an already-persisted RESULT with the
canonical RESULT before VERIFY-only recovery (mismatch: exit 33). The current
kernel generation is supplied to canonical ingestion. Immediately before ingest,
recovery replays the current trusted plan+journal again. The sequencer routes
the objective from its effective header and operand from its effective node into
the final eight words of canon's 23-word expected record; neither pin comes from
the submitted document or bundle. Stale receipts with changed operands refuse
at the earlier operand check (exit 24). A correction round-trip returning to the
original operand isolates stale-generation refusal (exit 14). These decisions
remain in Omega, not shell admission rules.
`recovery-build.sh` checks the same e5b32567 compiler digest as canon-build.sh.

Effective-operand folding streams the unchanged kernel plan+journal bytes after
a `1\n` mode prefix, retaining only one event. It has no event-count ceiling.
The prefix is excluded from the byte count. The same input-size rule as
`kernel.om:10,60-79` applies: its 262144-byte buffer refuses input length
greater than or equal to 262143 (exit 3), including trailing whitespace.
`recovery.om` emits the updated 40-word header/node before the sequencer adds
the current status and explicit binding for canonical emission.

Build `canon` with the preceding pinned build command. Materialize the SHA
oracle source without modifying its checkout:

```sh
mkdir -p /tmp/aienet-m1-sha
git -C "$OMEGA_MV" archive 55845e70 om/sha256/sha256-om2.om |
  tar -x -C /tmp/aienet-m1-sha
taskset -c 10-14 nice -n 19 ionice -c3 env \
  OH_TREE=/home/drakestapleton/fix/aienet-oh-seal \
  PROTOCOLS=/tmp/aienet/aien-protocols-mv \
  OMEGA_WORKTREE=/home/drakestapleton/workspace/allen-harness-evolution-omega \
  RECOMPUTE_OMC=/home/drakestapleton/workspace/omega-mcp/build/omc \
  SHA_OMEGA_TREE=/tmp/aienet-m1-sha CANON=/tmp/aienet-m1-canon \
  bash tests/goal_microjobs/aienet-m1/run.sh /tmp/aienet-m1-fresh-output
```

The output directory must not exist. The harness builds both OH release
binaries from the explicitly supplied seal-document worktree and resolves
their executables from Cargo's reported artifacts, including when
`CARGO_TARGET_DIR` is set. It verifies the recompute pin and records the exact
OH revision, both OH binary digests, canonical source revision and canonical
binary digest in `summary.tsv`, with one expected/observed row per case.
`mutants.tsv` counts a mutant as killed only for its named semantic failure;
setup errors are not kills. Baseline failures prevent mutant qualification.

Cases cover happy completion; SIGKILL after bundle persistence, DISPATCH,
receipt plus AN0V publication and RESULT; worker SIGKILL after durable admission
and after durable completion; generation correction; signature-covered MJR1
mutation; executor-signed wrong output; duplicate receipt and an independently
signed second completion; signature-only AN0V mutation; and RESULT-only recovery
with a kernel-valid but conflicting persisted time charge. Negative self-tests
prove the DONE helper rejects RESULTED, missing and duplicate node-1 status
records. History regressions exercise multiple CORRECTs, 257 and 1000 CORRECTs,
and two CORRECTs after a persisted RESULT. Capacity probes check the largest
accepted kernel input and refused boundary/over-capacity inputs against both
kernel and recovery, with matching observed exits in `capacity.tsv`.
Authenticated substitution regressions replace a complete validly signed job,
receipt and countersign after publication but before ingest. Different objective
and operand substitutions must pass Open Humanity's pinned-key check but refuse
at canon with 23 and 24 respectively, emit no events, preserve the journal and
leave the generation running. A generation-two pre-CORRECT operand substitution
also refuses with 24. Restoring the original checked bytes then completes the
same dispatch exactly once. Observed exits are filed in `pin-refusals.tsv`.
Guard-removal mutants challenge persist-before-DISPATCH, check-before-ingest,
current-generation routing and Omega RESULT conflict checking. A fifth mutant
stops folding after the first CORRECT; the last-CORRECT regression must kill it.
Two further mutants pass the submitted document's own objective or operand as
the expected pin; the authenticated substitution cases must kill both.
Every accepted generation has one DISPATCH, RESULT and VERIFY.
Recovery checks that persisted bundle bytes never change.

All identities and payload bindings here are explicit synthetic test values.
Disposable private scalars are generated by `openssl rand -hex 32` in an
owner-private `/dev/shm` directory and deleted on exit. Only loopback ephemeral
ports are used; workers have owned state directories and owned process IDs.
No GPU, model server, P1 second machine, P2 federation, Core TUR settlement,
production deployment or hardware qualification is exercised by this harness.
