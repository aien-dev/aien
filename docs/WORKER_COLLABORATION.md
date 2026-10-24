# Allen worker collaboration contract

## Role split

Allen receives the request, chooses whether a worker is needed, selects a bounded task strategy, and presents the verified result. Qwen3.6-35B and Qwen3.8-27B are specialist workers. They do not speak as Allen, choose their own permissions, approve their own output, or write lessons directly.

The intended complementary pattern is:

- **Qwen3.6-35B: fast first pass.** Generate a bounded initial plan, identify likely context or skill changes, and make progress on independent subtasks when the task permits.
- **Qwen3.8-27B: deliberate analysis.** Review task interpretation, examine risks and edge cases, compare candidate strategies, or handle work that benefits from more reasoning time.
- **Allen: coordinator and integrator.** Give each worker only the task material and capability envelope it needs. Reconcile disagreement, request a bounded follow-up when justified, and submit artifacts to the independent verifier.

This is a proposed division of labor, not a claim that either model currently has those measured characteristics. The 27B and 35B capabilities, speed, availability, tool support, and privacy scope must come from their exact qualification records. A worker's answer is untrusted task data. Agreement between the two workers is not independent verification.

## Response conversation shape

After the existing Core Responses API owner delivers a qualified native `client.responses.create(...)` path, Allen may run a bounded conversation with these steps:

1. Allen sends the same pinned task statement, permitted context references, strategy candidate, and resource limits to the admitted worker or workers.
2. The fast worker may return an initial result and explicit unresolved questions. Allen may send that result to the deliberate worker as untrusted review material, with the original requirements still attached.
3. The reviewing worker returns findings, counterexamples, or a separate alternative. It cannot alter the task requirements, scoring rules, trusted verifier, policy, permissions, or other worker's identity.
4. Allen records both outputs and their exact model/session identities, resolves disagreements, and passes each candidate artifact to the existing independent verification path.
5. Allen selects the unchanged baseline or the best candidate supported by verified evidence. If neither candidate qualifies, Allen uses the baseline or abstains.

The runtime, not model text, controls response continuation, tool execution, cancellation, budgets, and session ownership. Any tool call requires the existing capability gate. A response returned by the model service never executes a tool by itself.

## Model and API status

| Worker | Intended role | Current integration evidence | Harness status |
|---|---|---|---|
| Qwen3.6-35B-A3B-FP8 | Fast proposal and bounded progress | Operator reported `http://127.0.0.1:18091/v1`, Chat Completions only, and request-time thinking control. Core #736 tracks the native Responses API path. | Disabled; no inference run in this implementation. |
| Qwen3.8-27B | Deliberate review and complex reasoning | Exact endpoint, API, capability manifest, and availability are not verified here. | Included in the evaluation manifest as unqualified; disabled; no inference run. |

Core #735 owns model admission and dispatch. Core #736 owns the local model service's complete Responses API support. Allen must not add a competing adapter, server, or route around either owner. The current host could not be reached for live qualification, and the protected 35B service was not restarted or reconfigured.

The feature remains default-off/shadow-only. Real model calls require both the relevant protocol and worker admission gates, and both model paths remain subject to separate qualification. A 35B failure or missing route does not authorize automatic fallback to the 27B, or vice versa.

## Limits and evidence

Every multi-worker turn consumes the same task experiment budget as a probe. The initial Alpha ceiling is two refinement rounds, eight extra candidate executions per task, and two concurrent workers. Each request also needs explicit token, time, memory, compute, and spending bounds enforced outside the model. Incomplete, cancelled, refused, or missing responses are recorded separately from failed verified outcomes.

The four-arm evaluation freezes model versions and task/evaluator contracts. It records the cost of both workers, all response turns, preparation, verification, retries, and recovery. The proposer cannot change the evaluator, inspect sealed final tasks, or promote its own lesson. No performance or quality advantage is claimed until the frozen real-model evaluation is independently judged.
