# M2: persistent bot records and durable inboxes

PROPOSED local component for the [bot-network plan comment](https://github.com/aien-dev/aien-architecture-mv/issues/311#issuecomment-6511785962), coordinated on architecture issue #311, whose title is TURING NETWORK R0. Not a master plan, network schema, capability, or new subject identity.

## Owners and source map

Design read against aien main `b02bc7fb8c28bf90803d5bd357d1749cabdfc974`, architecture ADR 0035 (LogicalAgentId + AgentRoot) and ADR 0022 (canonical Omega rx_cortex single writer). Open Humanity `crates/oh-core/src/identity.rs` owns Ed25519 identity provisioning through atlas-vault. This tool accepts only its public key, never a private seed; it neither signs nor proves key ownership. Registering requires an already trusted local caller. No auto-enrollment.

The bot id is an address for a local record bound to the existing subject, not a replacement LogicalAgentId or AllenId. Derivation is SHA-256 of ASCII `AIEN-BOT-V1`, one zero byte, OH Ed25519 public key (32 bytes), LogicalAgentId (32 bytes), AgentRoot reference (32 bytes). Registration stores those bindings immutably. Display name is 1..64 printable ASCII bytes. Skill refs, routine refs and Cortex memory refs are each ordered lists of up to four opaque nonzero 32-byte ids. A zero slot means absent. Memory contents, claims, promotion and planning stay with Cortex/JSpace; no Cortex writes occur.

Worker leases are separate records referencing bot_id. Rotating a lease never changes bot identity, registration, or memory references. Model residency is a separate owner record referencing bot_id; no model, seat, weights, process, budget or routing field is stored in the bot record. A lease token is a nonzero opaque 32-byte id, never reused for this bot within a journal. This is local optimistic ownership, not cryptographic authorization.

Core `crates/spark-hive/src/store.rs` ForgeTask/HiveComb remain task/comb records in SQLite, not bot identity or a second inbox. AEGIS `src/sessions/session.rs` remains session state, messages, profiles and budgets, not bot continuity. No automatic migration or caller cutover is claimed: this new CLI has no existing runtime consumers. A future network binding belongs to aien-protocols, transport/signing to Open Humanity. This local journal is not a wire format.

## Inbox state machine

REGISTER, ROTATE, DELIVER, CLAIM, ACK, NACK, EXPIRE and RETIRE are typed events. Bots are active or retired; retirement is irreversible. DELIVER accepts recipient bot_id, sender bot_id (an opaque external reference), payload bytes and a nonzero handoff reference. Payload bytes are hashed and discarded: the journal retains only SHA-256(payload). Message id is SHA-256 of ASCII `AIEN-BOT-MESSAGE-V1`, zero byte, recipient id, sender id, payload digest and handoff ref: the content digest of that complete immutable envelope. Identical envelope delivery is idempotent, including after ACK, with no second event or inbox copy. Different sender, recipient or handoff is different content.

Messages are pending, claimed or acknowledged. CLAIM requires the bot's current lease and a pending message. ACK/NACK require both current lease and the message's recorded claimant. ACK is durable and accepted only once; any later ACK or claim is refused. Rotation makes old claimants stale but does not silently acknowledge or discard their work. EXPIRE explicitly returns a claim to pending only when its claimant is no longer current. NACK returns a current claim to pending. No timer, scheduler or wall-clock trust is introduced. Retired bots reject delivery (even duplicates), rotation and message mutations; show remains available.

## Durability design

The existing `src/goal_microjobs/kernel.om` is the typed replay/admission reference; its `scripts/goal_microjobs/microjobs.sh` owns flock, candidate replay and sync/rename. Here those mechanics live in the Omega binary itself: a stable JOURNAL.lock inode is locked exclusively, even for show, then JOURNAL is replayed from zero. Accepted events extend the previous bytes without modifying historical event bytes. The candidate JOURNAL.cand is completely written, fsynced, renamed over JOURNAL, then the containing directory is fsynced before success output. A refused command leaves JOURNAL unchanged. A stranded candidate is never replayed and is overwritten under the lock. SIGKILL before rename leaves the old state; after rename leaves the new state. This is process-interruption evidence, not physical power-loss qualification.

Journal directories must be private and trusted; all callers must use one canonical path and this locking convention. Advisory locking is not protection against a malicious local writer, hardlink aliases, directory replacement or external file edits. The implementation refuses final-component symlinks for journal/lock/candidate. Existing journal bytes are integrity checked, not authenticated. Atomic replacement requires candidate and journal in the same directory. There is no network listener or background loop.

Bounded local storage: 64 bots, 256 messages, 1024 events. Each event is 1024 bytes, magic BJT1, type at byte 4, sequence at 8 (big-endian u64), bot_id at 16, typed body at 48, SHA-256 of bytes 0..991 at 992. All unused bytes are zero. REGISTER stores public key/logical/root at 48/80/112, name at 144 (zero padded to 64), skills/routines/memory at 208/336/464. ROTATE stores lease at 48. DELIVER stores sender/payload-digest/handoff/message-id at 48/80/112/144. CLAIM/ACK/NACK/EXPIRE store message-id/lease at 48/80 (EXPIRE lease is the stale claimant). RETIRE has no body. The committed journal is authoritative; no state cache is persisted.

## CLI and acceptance

Shell is limited to the pinned build adapter and acceptance harness. Runtime parsing, hashing, journal IO, replay and admission are Omega. This is a Linux aarch64 executable, not a portable filesystem layer. Payload arguments are limited to 4096 bytes, journal paths to 2047 bytes, and ids use exactly 64 lowercase hex characters. Reference lists use comma-separated ids, or `-` for none. Strings are literal argv bytes, not JSON.

```text
bots register JOURNAL OH_PUBLIC_KEY LOGICAL_AGENT_ID AGENT_ROOT NAME SKILL_REFS ROUTINE_REFS CORTEX_REFS
bots rotate JOURNAL BOT_ID NEW_WORKER_LEASE
bots deliver JOURNAL BOT_ID SENDER_BOT_ID PAYLOAD HANDOFF_REF
bots claim JOURNAL BOT_ID MESSAGE_ID WORKER_LEASE
bots ack JOURNAL BOT_ID MESSAGE_ID WORKER_LEASE
bots nack JOURNAL BOT_ID MESSAGE_ID WORKER_LEASE
bots expire JOURNAL BOT_ID MESSAGE_ID STALE_CLAIMANT_LEASE
bots retire JOURNAL BOT_ID
bots show JOURNAL
```

Successful mutations print `OK <bot_id>`, except DELIVER prints `OK <message_id>`. Repeated DELIVER prints `DUPLICATE <message_id>` without appending. Refusals print `REFUSE <code>` and exit with that code; success exits zero. `show` emits registration-order `BOT <592-byte-event-prefix-hex> <status>`, `LEASE <bot_id> <lease-or-zero>`, then delivery-order `MESSAGE <160-byte-envelope-hex> <state> <claimant-or-zero>`. Bot status is 1 active / 2 retired; message state is 1 pending / 2 claimed / 3 ACKed. The BOT prefix includes original sequence, binding, display and all references; the MESSAGE prefix includes recipient, sender, payload digest, handoff and message id. No wall time or worker/model-dependent text occurs.

| Exit | Refusal |
| --- | --- |
| 2 | Usage, malformed hex/reference list/name/path or oversized argument |
| 3 | Filesystem, output or syscall failure, including final-component symlinks |
| 4 | Zero id/reference supplied through CLI |
| 5 | Bounded bot/message/event/journal capacity |
| 6 | Invalid journal type, framing, canonical body or derived identity/content id |
| 7 | Noncontiguous event sequence |
| 8 | Record checksum mismatch |
| 9 | Exclusive lock unavailable |
| 10 | Bot already registered |
| 11 | Bot not registered |
| 12 | Bot retired |
| 13 | Worker lease token previously used for this bot |
| 14 | Message not found in this bot's inbox |
| 15 | Stale, foreign or absent current worker lease |
| 16 | CLAIM requires pending state (including claim after ACK) |
| 17 | ACK/NACK/EXPIRE requires claimed state (including repeated ACK) |
| 18 | Supplied worker lease is not the message claimant |
| 19 | EXPIRE requires a stale claimant, not a live claim |

Refusal precedence follows framing/integrity, replay, then the requested transition. Retirement precedes duplicate-delivery handling. A storage failure after rename may leave a committed event without success output: retries must inspect/replay state, not assume refusal means no commit. Exactly-once ACK refers to admission of the ACK event, not exactly-once execution of an external action. There are no external actions here.

## Reproducing host acceptance

The build adapter checks `omc` SHA-256 `2c82480596bbdc50cda9626866209ef662d5834f278f839ff4ce0250c495029f` (Omega `e5b32567`). It composes the unchanged first-party seeded SHA-256 unit `om/sha256/sha256-om2.om` at `55845e70`, SHA-256 `dbf002dd6aa36585632b9d01d98ac3f0bd2fa0f0475082940de53638847994bb`, with this runtime. Only export declarations are removed when composing the unit. No foreign crypto implementation is linked.

```sh
taskset -c 10-14 nice -n 19 ionice -c3 env PYTHONDONTWRITEBYTECODE=1 \
 OMEGA_OMC=/home/drakestapleton/workspace/omega-mcp/build/omc \
 OMEGA_MV=/home/drakestapleton/workspace/bridge-g1-mv \
 BOTS_RUN_ROOT=/home/drakestapleton/handoffs/aienet-m2/round2 bash tests/bots/run.sh
```

Use a fresh external run root. The harness records `transcript`, `mutants.tsv`, `results.txt`, source/compiler hashes, exact fixture journals, show output and mutant build/probe transcripts. Independent `sha256sum` checks both public identity derivation and envelope content identity. Capacity fixtures are constructed by the harness, with independently recomputed SHA-256 checksums, not generated through a fake runtime.

Each catalogued admission/integrity guard (`BOT-GUARD` in the source) gets a precise failing negative control and a separately compiled sed-patched removal mutant. `mutants.tsv` preserves expected and actual binary exits separately from the assertion-child exit. Semantic admissions are `KILLED_ADMIT`; changed valid refusal codes are `KILLED_CODE`; output/state/barrier mismatches have distinct `KILLED_OUTPUT`, `KILLED_STATE`, `KILLED_BARRIER` verdicts. Omega traps (101..114), signals and infrastructure/build failures are `TRAPPED`, `SIGNALLED` and `ERROR`, never kills. Removing botcap/msgcap checks hits fixed-size array bounds (exit 103, trap 3), so these two controls are honestly TRAPPED, not semantic counterexamples. No extra allocation is introduced solely to make a mutant admissible.

The corpus additionally checks usage, missing bot/message, filesystem refusals, lock contention and symlink refusal. `BOTS_KILL=1` through `6` is a deliberately explicit test-only fault seam: SIGKILL after candidate open, prefix write, event write, candidate fsync, rename and directory fsync. Eight event types exercise every boundary. Replay must match exact old/new committed bytes and deterministic show output; a truncated candidate is ignored and replaced. A required strace oracle tracks actual candidate/directory descriptor opens and asserts successful `fsync(candidate)` then `renameat2(candidate,journal)` then `fsync(directory)`. Separate mutants remove each fsync and move rename before candidate fsync. Missing strace fails closed with NOT_RUN, not PASS. This establishes commit-barrier ordering evidence, not power-loss qualification.

Compiler restrictions encountered, with no dropped behavior: error 19 at composed line 484 (global arrays cannot be passed as views) was resolved by selector-based bounded copy/access functions and local SHA buffers; error 12 at composed line 621 (register pressure) by splitting reference decoding into temporaries; error 8 at composed line 390 (loop bound too large) by using the supported 999999 bound. No compiler extension or host runtime fallback was required.

Owner reference revisions: architecture `c6512a4c6ae2e8f8babe23fc9f38880d20d25812`; Open Humanity `53c39bf2031c01e28703dfdad7e8cae89de2d756`; Core `b65e00b0652a3b426dce1bf77f7fe4eccf5f7473`; AEGIS `a39788b0eaaabc694dfa17652420e35b7dc3eda5`. This adds a local component, not a change to language syntax, compiler ownership, wire schemas, gates or model serving.

P1 two-machine, P2 federation, signing/key-ownership proof, Cortex integration, network transport, scheduling/model routing, power-loss testing and hardware qualification: **NOT_RUN**, outside this change. No merge or deployment is claimed.

## Host receipt

The earlier round-one claim of 33 semantic mutant kills is withdrawn: two capacity mutants actually trapped at fixed array bounds. Historical evidence under `/home/drakestapleton/handoffs/aienet-m2/acceptance-final/` is unchanged; round-two evidence and corrected per-verdict results live separately under `/home/drakestapleton/handoffs/aienet-m2/round2/`. Only host behavior and barrier ordering are exercised, not two-machine, federation, power-loss or hardware qualification.
