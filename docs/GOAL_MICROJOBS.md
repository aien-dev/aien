# Goal to typed microjobs (Allen #13)

Allen keeps one persistent objective as a typed, dependency-bound microjob DAG plus an append-only event journal. The seeded `.om` kernel `src/goal_microjobs/kernel.om` is the only admission logic: it replays plan + journal from stdin and either prints the derived state or refuses with a code. It runs no job, calls no model, and writes no memory or authority state. The model or planner proposes; the kernel decides what is admitted.

Status: **IMPLEMENTED, HOST_TESTED (offline, synthetic fixtures)**. Not run: model inference, Omega/Core dispatch, Cortex write/restart, canonical MJB1 binary ABI, routing comparison, GPU or physical qualification. Deployment OFF.

## Boundary

| Here (Allen) | Owner elsewhere |
|---|---|
| Objective plan records, journal replay, admission refusals, derived node state, objective receipt line | Execution of a node: Omega scheduler / FORGE placement; worker admission: Core #735 |
| Retry, budget, cancellation, correction and effect-once rules over the journal | Canonical wire ABI: aien-protocols-mv#50 (`specs/microjob/SPEC.md`, MJB1/MJR1 draft) |
| Local journal file in an owner-private directory (mode 700) | Durable memory: Omega Cortex (ADR 0022); the Cortex writer adapter does not exist yet |

The journal is not Cortex and is not a second memory store: it is the local replay log of one objective until the Cortex owner publishes a typed writer. The existing transitional shell (`scripts/goal_microjobs/microjobs.sh`) handles files, the `flock` lock and the atomic rename. Current seeded Omega has file and argument APIs; the shell has not been migrated. The NL-5 shadow experiment below does not invoke this writer.

## Records (local adapter, pending aien-protocols-mv#50)

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

Checked against `specs/microjob/SPEC.md` draft v0.1 on aien-protocols-mv branch `feat/si-microjob-capsule-abi` at `33e28b9a2b381d9eb2089e866c4f377bcd61b1a9` (not merged). Same closed values: kind (1 COMPUTE, 2 NEURAL), op ranges per kind, profile 0..4 with caps 64/16, 128/32, 256/64, 512/128, effect class 0/1/2 bounded by the header ceiling, verifier kind 1..3, retry class 1..3, max attempts 1..8. Same rules: COMPUTE spends zero tokens; required tokens above caps refuse as needs-expansion (no silent truncation); NEVER with more than one attempt and EFFECT with IDEMPOTENT refuse; sums of node input-token, output-token and time caps stay within header budgets, summed exactly; node tenant equals the objective tenant; dependency cycle refuses. Allen-local guard, not an MJB1 rule: the kernel refuses (26) a node whose input-token, output-token or time cap exceeds 2^32 - 1, so its 64-bit sums of at most 64 nodes cannot overflow. MJB1 stores those three fields as u16, u16 and u32, so the guard never refuses a value MJB1 can encode. MJB1's u64 fuel, memory and work caps (exact sums; a total that does not fit 64 bits is `MJB_OVER_BUDGET`) are not checked by this kernel yet.

Allen-local and to be replaced by the canonical ABI: decimal text instead of big-endian bytes; small integer identities instead of 32-byte subject, capability, model and verifier references; `route` (1 reflex, 2 student, 3 qualified teacher) standing in for `model_ref`; `required` and `terminal`; per-event generations instead of a re-issued document per generation; journal events instead of signed MJR1 receipts. MJR1 outcomes map as RESULT+VERIFY → COMPLETED, REFUSE → REFUSED, FAIL → FAILED, CANCEL → CANCELLED. Fuel, memory, work, precision, substrate, expiry, operand kinds and P-256 receipt signatures are not checked here yet.

## Restart, partial completion and duplicates

Every `propose` takes the lock, copies the journal to `journal.cand`, appends one event, replays plan + candidate through the kernel, and only on exit 0 runs `sync` and renames the candidate over the journal. A writer killed before the rename leaves the journal unchanged; a restarted process replays the same bytes to the same state. A running lease left by a stopped process is closed by a runtime FAIL and retried as a new attempt; the late result of the old attempt and any repeated result or effect are refused.

## Reproduce

```sh
OMEGA_WORKTREE=<seeded Omega worktree at c434565c> bash tests/goal_microjobs/gate.sh
```

`scripts/goal_microjobs/build.sh` checks the same Omega commit and compiler pins as Allen #12's harness gate. The gate writes `evidence/goal-microjobs/offline-*/` (unsigned receipt, transcript, final status and journal, mutation table).

The 12-node acceptance objective runs nodes 1 to 4 concurrently before the join at node 7; it has five COMPUTE nodes with zero tokens before the correction, three bounded NEURAL routes, one refused optional teacher route, one model failure with retry, one interrupted lease after a SIGKILL'd writer, one rejected model answer with retry, and one owner correction of node 3 that resets exactly nodes 3, 7, 8, 9, 10, 11, 12. Expected totals, recomputed with the Wolfram Language evaluator: tokens reserved (60+12) + 2(120+30) + 4(120+30) = 972; tokens used 50+40+110+120+118+116 = 554; time 12531 ms; 18 attempts; 7 model calls; static caps 800 input, 192 output, 18800 ms against budgets 1000, 256 and 20000.

## Open

- Bind to the canonical MJB1/MJR1 bytes once aien-protocols-mv#50 lands (reader in `.om` or through the protocol's reference reader).
- Cortex writer and restart through the Omega owner; Core #735 worker admission and dispatch; qualified-worker registry for route selection.
- Objective text to DAG rule baseline and shadow route policy; ordinary routing vs microjob comparison; native `.om` plan export.

## NL-5: default-off private-local shadow experiment

Issue [#19](https://github.com/aien-dev/aien/issues/19), parent
[architecture #349](https://github.com/aien-dev/aien-architecture-mv/issues/349).
This is a synthetic host experiment, not a serving route or a learned channel.
The source is stacked on the unchanged #13 kernel at
`52067ba2ec2e631db017fb9e700f31c048f1a12d` (PR #14).

`src/goal_microjobs/shadow.om` emits an Allen-local plan and proposed journal.
Only the existing `kernel.om` admits that journal. It does not call the
transactional writer, execute effects, open files or sockets, read activations,
write Cortex, create an identity, or change ordinary routing. No arguments
means exit 64 with no output. Exact opt-in is
`--private-local-shadow A|B|C SCENARIO`; no arbitrary task, trace or endpoint
input is accepted. All data is fixed public synthetic fixture data. Runtime
scratch expires on process exit; private-local redirects should use `umask 077`.
Local opt-in grants no publication, training or Open Humanity consent.

### Paired arms and invariant task

- A: deterministic text specialist. Each hop serializes `add X Y`, parses it,
  and returns the arithmetic result. This is a constrained text stub, not
  ordinary Allen-to-model routing or an NLP quality result.
- B: deterministic typed specialist. Each hop serializes three little-endian
  u64 fields (operation 1, lhs, rhs), decodes them and computes the same result.
  This is an internal test message, not MJB1 or SEM-WIRE.
- C: unsupported latent interface; explicitly reports `NOT_RUN` and falls back
  to B. It never treats a numerical message as authority. Scenario 4 injects a
  bad proposed value into the stub, requires its independent rejection, then
  recomputes from the original typed operands. This tests fallback mechanics,
  not a trained projector or the actual LTP0 decoder.

All arms share the exact objective, owner 7, Allen runtime 9, verifier 5,
worker 20, pure effect ceiling 0, dependency graph and budgets. These small
identifiers and result words are explicitly Allen-local synthetic references,
not canonical identity/digest claims. The 12-node graph has four roots, a join
at node 5, a chain to required terminal node 11, and optional node 12.
Node 4 exercises the existing bounded NEURAL admission class without inference.
The same attempt/model/token/time caps are emitted for each normal arm. The
new harness also charges every specialist attempt, including fallback, against
the same 32-call work cap, with a fixed 128-byte message buffer and bounded
loops. The native conductor applies the same default child deadline to all
arms. Plan token/time fields are reservations and synthetic charges, not
observed model tokens or elapsed wall time.

The independent oracle is Wolfram, not another invocation of the specialist.
Raw verification calls and task query/results are in
`evidence/nl5-wolfram.jsonl`; the fixed expected table is
`tests/goal_microjobs/shadow-oracle.om`. Every proposed result is compared
before verifier verdict 1. A rejected result never completes the objective.
Initial terminal value is 65; correcting node 3 changes it to 66. These are
oracle values from the filed Wolfram output, not performance statistics.

| Scenario | Exercised behavior |
|---|---|
| 0 | Complete the equivalent pure objective; optional node 12 refused |
| 1 | Owner correction invalidates affected generations; verified terminal changes |
| 2 | Cancel node 5 and descendants; objective blocked, never complete |
| 3 | Stop at four completed roots; saved prefix replays and full journal restarts identically |
| 4 | Wrong result: A/B exit 65 with verifier rejection; C stub refuses it and recomputes typed fallback |
| 5 | Dispatch before dependencies: kernel exit 43 |
| 6 | Correction by worker, not owner: kernel exit 39 |
| 7 | Exhaust neural admission budget: kernel exit 37 |
| 8 | Attempt effect in pure shadow: kernel exit 44 |
| 9 | Duplicate result after completion/replay: kernel exit 33 |

### Reproduce and evidence

Compiler source is Omega PR #919 at
`e79566c191ea8ef11888e69ce50d8fadf375d4fd`; committed `seed/out/omc`
SHA-256 is `d6290c7663c2b4bafb59eb3fdf812476e977f4c144def71095c6248ef9b96b84`.
This binary was introduced by upstream commit
`1fe5976d398646b17acabbf6d9dfae96b017e439` (diagnostics/Qty), not a local
rebuild. The older 2c824805 and 49923639 guide pins are different compiler
revisions and must not be substituted silently.

From a private disposable directory, set `AIEN` to this checkout and `OMEGA`
to that exact Omega checkout. Shell below only invokes the compiler and native
conductor; no new shell runner is shipped.

```sh
umask 077
ln -s "$AIEN" candidate
ln -s "$OMEGA/seed" seed
ln -s "$OMEGA/seed/out/omc" omc
sha256sum omc
./omc < seed/qualification/om2/gate.om > gate &&
chmod 700 gate &&
./gate ./omc d6290c7663c2b4bafb59eb3fdf812476e977f4c144def71095c6248ef9b96b84 \
  candidate/tests/goal_microjobs/shadow.cases native-final
```

The conductor composes `shadow.om+shadow-oracle.om`; both are handwritten
seeded Omega. It replays all arm/scenario outputs and independently runs the
unchanged admission kernel against each. The `.cases` file also removes the
oracle guard, removes typed fallback, bypasses opt-in, and exhausts the shared
work budget. Recorded exact outputs are `evidence/nl5-*.planjournal`,
`*.status` and `*.trace`. Trace rows `201 node arm_ascii handoff_bytes` count
actual serialized hop bytes, including recomputation; `202 4` marks the
injected bad-proposal refusal. Header bytes, model token counts, codec timing,
queue/verification overhead, p50/p95, Turing yield and comparative economics
are **NOT_RUN**, not zero or an implied improvement. The ASCII arm tag is not
an identity. `nl5-host.json` records source/binary hashes and the independent
oracle/replay checks; `nl5-native.log` is the native gate transcript.

### External interface remains fail-closed

NL3 owns LTP0 and NL4 owns `nlproposal`/`nlmatch`, not this repository. Their
proposal-only interface does not provide canonical MJB1 CONTENT digest binding,
durable nonce/sequence reservation, capability authorization or signed receipt
admission to the current Allen decimal adapter. The owning gaps are
[protocols #70](https://github.com/aien-dev/aien-protocols-mv/issues/70) and
[AEGIS #79](https://github.com/aien-dev/aegis-runtime-mv/issues/79). NL4's
closed inc/double/id fixture is not equivalent to this arbitrary-add graph.
Therefore actual LTP0/semantic-boundary integration, wrong-basis/model-swap/
expired-projector negotiation and learned C transport remain **NOT_RUN**,
with a truthful typed fallback, not forged trust flags. The adapter boundary
must consume those owner APIs before C can become eligible.

Real-model runs are **BLOCKED** by the explicit no-serving/no-activation/GPU
authorization boundary. The research outcome is **INCONCLUSIVE**: no latent
quality, generalization, speed or economic result is claimed. No live route,
public endpoint, promotion, Cortex writer or release gate changes are included.
The independent benchmark preregistration is
[benchmarks PR #56](https://github.com/aien-dev/benchmarks-mv/pull/56),
commit `8ee0a494bf73230c9d37647eb3caea792298fa8d`.

