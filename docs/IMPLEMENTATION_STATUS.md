# Harness Evolution Alpha implementation status

Status is recorded against Allen #12's MAC-1 through MAC-8 gates. **Overall implementation: INCOMPLETE.** **Adaptive behavior approval: NOT_RUN.** Runtime activation remains OFF.

## Evidence produced

- Seeded Omega source-aware compiler gate: PASS, 10,000 valid inputs, 100,000 malformed inputs, 131,000 requests, and 9 compiled mutants. This is the existing Omega gate, not Allen acceptance evidence.
- Seeded bounded-recursion replay: PASS, 3,464 observations, zero mismatches, and 6 mutants. This is also an existing Omega gate.
- Allen native decision fixture: FAIL at native execution. Reproduction command from the isolated Allen worktree:

  ```sh
  OMEGA_WORKTREE=/home/drakestapleton/workspace/allen-harness-evolution-omega \
  SA_SEED_REPO=/home/drakestapleton/workspace/omega-bridge \
  bash scripts/harness_evolution/gate.sh
  ```

  Observed exit status: 103. The source-aware and bounded-recursion sub-gates completed before this failure. The latest unsigned failure receipt is `evidence/harness-evolution/offline-20261024T143158Z-Bzwtcv/receipt.json`. The fixture has no captured stdout or stderr for the native failure, so its exact cause is not established. The previous selector-only PASS receipt predates the current candidate/observation schema and does not qualify this expanded implementation.
- Independent architecture review found the earlier kernel incorrectly tied sequential ancestry to the current best result and did not enforce measured usage bounds. The expanded kernel addresses those paths in source, but the current native fixture failure means those changes remain unaccepted.
- Spark RSI has an offline four-arm manifest proposal in its separate required review branch, PR #69. It lists both model seats as unqualified and routes disabled. It is fixture scope only, not the required 30-task independent evaluation or signed judge result.

## Gate status

| Gate | Status | Evidence or missing proof |
|---|---|---|
| MAC-1 native execution connected to Allen | BLOCKED | `.om` candidate/decision kernel exists, but no Allen application entry point exists in current main. This fixture fails native execution with exit 103. |
| MAC-2 editable context and skill strategies | NOT_ACCEPTED | The typed contract defines both scopes. Runtime validation and consumption are not integrated. |
| MAC-3 parallel and sequential exploration | NOT_ACCEPTED | Kernel and fixtures are present. No passing current native gate or executing isolated probes. |
| MAC-4 security and negative controls | NOT_ACCEPTED | Some synthetic rejection cases are represented. Verifier/receipt claims still arrive as caller-provided fields, and mutation suite did not run on the current failure. |
| MAC-5 memory across restart | BLOCKED | No Allen-to-Omega Cortex adapter or local restart/reuse fixture. Existing Cortex owner must supply the typed interface. |
| MAC-6 30-task four-arm evaluation | NOT_RUN | RSI proposal is not the frozen complete suite, independent judging, or full cost report. |
| MAC-7 reproducible end-to-end workflow | BLOCKED | Current native execution fails; no memory-owner write/restart/reuse workflow or independent receipt. |
| MAC-8 safe activation | PARTIAL | Documentation specifies disabled/shadow defaults; no Allen runtime exists here to prove default-off behavior. No service or route was changed. |

## Model collaboration and Response API

The proposed complementary worker roles and bounded Responses conversation are in `docs/WORKER_COLLABORATION.md`. It preserves Allen as the sole front door and treats both specialist outputs as untrusted data. The concept is not yet executable.

- Core #735 owns qualified worker admission and dispatch. Its current main describes an owner-approved seeded `.om` ABI and requires both independently qualified model seats. No Allen integration ABI is available in this worktree.
- Core #736 owns complete native Responses API support. Current Core main is Chat Completions only. Core #736 requires the Responses request/output contract, streaming, tool-call continuation, bounded response state, capability discovery and negative controls. No adapter or server/client configuration was added here.
- Qwen3.6-35B-A3B-FP8 endpoint and Chat Completions details are operator-reported only. The live host was unreachable from this session. No inference was attempted, and the service was not restarted or altered.
- Qwen3.8-27B remains included in the RSI model-seat manifest. Its endpoint, API, capability profile and availability are not verified. Its route stays disabled.

## Required next verification

1. Reduce the native exit-103 case to a small compiled `.om` fixture and identify whether the defect is in the Allen kernel or the seeded compiler/runtime. If it is a language defect, attach that exact fixture and command to the responsible Omega owner issue before relying on the affected behavior.
2. Integrate against the accepted Core #735 ABI and Core #736 native Responses client path after those owners publish verified artifacts. Keep the 35B and 27B seats independently qualified; do not call either endpoint before authorized gates.
3. Connect verified lesson claims to the existing Omega Cortex writer and restart/retrieval path. Keep evaluation, signing and promotion in Spark RSI.
4. Freeze and independently judge at least 30 held-out tasks across A/B/C/D with complete lifecycle costs, then separately assess adaptive behavior. Keep deployment disabled pending explicit authorization.
