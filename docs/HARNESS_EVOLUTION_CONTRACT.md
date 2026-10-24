# Allen Harness Evolution Interchange Contract

**Status: PROPOSED. Qualification: NOT_RUN.** This document freezes the logical record shapes for the bounded Allen Harness Evolution pilot. It does not implement a runtime, a wire protocol, a memory store, a judge, or a promotion service.

Issue: [aien-dev/allen#12](https://github.com/aien-dev/allen/issues/12). Scope: MAC-1 through MAC-8, with the initial candidate edit surface limited by MAC-2 to scoped context selection and skill selection guidance. This is an Allen-owned data contract, not a new master plan or a runtime authorization contract.

## 1. Authority and ownership

The current `aien-dev/allen` main branch contains the mission, phase ledger, and P0 plan. `docs/SOURCE_MAP.md`, `docs/OWNERS.md`, and `docs/B0_ACCEPTANCE_CONTRACT.md` are absent from main. The source map and B0 contract inspected for this work are proposals on `map/v0` and `contract/v0`; they are useful ownership references, not accepted main-branch authority. This contract is grounded primarily in the current MAC-1 through MAC-8 criteria in Allen #12 and the accepted architecture decisions linked below. Reconcile it when the P0 map and contract streams land.

| Concern | Owner and boundary |
|---|---|
| Candidate, experiment records, Allen evaluation manifests | Allen owns the logical records for its bounded research and acceptance work. |
| Allen identity and SubjectState | AIENOS and architecture ADR 0035. These records carry opaque references only. They cannot create or change identity. |
| Model/worker admission, skills, execution, AEGIS, tools and effect authority | Sovereign Core, Omega and their existing runtime contracts. This contract can request a route or skill selection; runtime policy decides whether it may run. |
| Canonical Cortex lesson writes and promotion | Omega `rx_cortex`, the single-writer Cortex owner under ADR 0022. Allen emits a lesson claim and never appends to or promotes Cortex records. |
| Skill body edits and rollback | Omega skill ledger owner under #563. The MAC-2 pilot changes selection guidance only; it does not edit skill bodies. |
| Evaluation and signed receipts | Existing Spark RSI judge and receipt pipeline under #67/#68. Candidate authors do not control the rubric, signer, or promotion decision. |
| Transport or cross-repository wire encoding | Existing `aien-protocols` owner. This document defines logical records only. Any network/wire form requires a separate protocol-owner review and reuse of the existing protocol repository. |
| Whole-system release and Alpha support claims | Architecture #190 and Alpha #305. A pass here cannot change their release or model qualification state. |

ADR 0035 defines the durable Allen subject boundary; it does not make the subject object a scheduler or permission authority. ADR 0024 describes Rust scaffolding and Omega as the destination; Allen #12's later `.om`-only requirement governs new first-party computation. This document contains no computation.

## 2. Shared scalar types

These are logical types, independent of any JSON, binary, or network encoding.

```text
SchemaId       = ASCII identifier with major version, e.g. "aien.harness.candidate/1"
ContentId      = { profile_id: ProfileId, digest: ByteString[32] }
ProfileId      = opaque identifier for an owner-approved canonical content-digest profile
OpaqueRef      = owner-issued reference; it carries no authority by itself
EvidenceRef    = { owner: RepoOrSubsystemId, object: OpaqueRef, content_id: ContentId }
ArtifactRef    = { artifact_kind: ArtifactKind, content_id: ContentId }
TaskFamily     = one of the closed values in section 3
ScopeRef       = { visibility: Visibility, owner_scope: OpaqueRef, session_ref: Option<OpaqueRef> }
Visibility     = operator_private | public_safe
```

`ContentId` is not an Allen identity, a user id, a path, or a capability. Allen does not choose the digest profile. Before a producer can create a candidate or a consumer can accept one, Omega must identify the canonical content-digest profile already used for the relevant `.om`/semantic identity surface and provide conformance vectors. Until then, implementations may carry `ContentId` opaquely but must reject unverified identities. Do not invent a second digest algorithm or compute a parallel identity-to-memory lineage digest.

Raw task text, private conversation text, retrieved source contents, tool arguments, credentials, model reasoning, and evaluation answers are not fields in these shared records. Private records remain on the owner's machine; any public reference must identify only approved public-safe material.

## 3. Candidate v1

```text
CandidateV1 = {
  schema_id: SchemaId,                         // exactly "aien.harness.candidate/1"
  candidate_id: ContentId,                     // identity of the canonical candidate body
  parent_candidate_id: Option<ContentId>,
  incumbent_id: ContentId,                     // unchanged baseline identity
  source: CandidateSource,
  source_evidence_refs: List<EvidenceRef>,
  task_family: TaskFamily,
  scope: ScopeRef,
  edit_scope: Set<ComponentKind>,
  diffs: List<ComponentDiff>,
  budget_profile_id: OpaqueRef,
  requested_caps: RequestedCaps,
  model_pin: ArtifactRef,
  tokenizer_pin: ArtifactRef,
  skill_catalog_pin: ArtifactRef,
  rationale_refs: List<EvidenceRef>
}

CandidateSource = allen_proposal | verified_lesson_reuse | operator_staged
ComponentKind   = context_selection | skill_selection_guidance

TaskFamily = compiler_debugging | coding | repository_analysis |
             research_synthesis | multi_step_planning | correction |
             refusal | ambiguous_request
```

For this pilot, the task-family list is closed. An unknown family is `UNSUPPORTED_TASK_FAMILY`; it must not silently map to a broader family. A task can be answered by the unchanged baseline without creating a candidate.

### 3.1 Allowed v1 diffs

`edit_scope` must equal the set of component kinds present in `diffs`. A duplicate kind, empty diff, undeclared kind, or mismatch is rejected.

```text
ComponentDiff = ContextSelectionDiff | SkillSelectionGuidanceDiff

ContextSelectionDiff = {
  kind: context_selection,
  expected_value_id: ContentId,
  replacement_value_id: ContentId,
  allowlisted_context_refs: List<OpaqueRef>,
  max_items: UInt32,
  max_bytes: UInt64,
  ordering: List<OpaqueRef>
}

SkillSelectionGuidanceDiff = {
  kind: skill_selection_guidance,
  expected_value_id: ContentId,
  replacement_value_id: ContentId,
  skill_catalog_pin: ArtifactRef,
  ranked_skill_ids: List<OpaqueRef>,
  excluded_skill_ids: List<OpaqueRef>,
  reason_codes: List<SkillSelectionReason>
}

SkillSelectionReason = relevant_to_task_family | evidence_needed |
                       unsupported_for_task | prior_verified_result
```

Context references must already be in the runtime-provided allowlist and in the candidate's owner scope. The edit selects references and applies lower retrieval count/byte limits. It cannot embed content, add paths, query another user, or convert retrieved text into instructions. Retrieved material remains untrusted data.

Skill ids must exist in the pinned catalog. Ranking is advisory. The runtime still checks the skill's current schema, availability, capability lease, tool arguments, privacy, budget, and approval policy. A selection record cannot invoke a skill, alter its body, create an argument, or broaden a skill's effects.

No other component kind is valid in v1. Task procedure text, memory-store behavior, tool authority/guidance that changes execution, delegation policy, deterministic helper code, lifecycle hooks, plugins, middleware, trusted prompts, and evaluator behavior are not editable by this pilot. Adding a future kind requires a new reviewed schema major and the owning subsystem's acceptance; unknown kinds always fail closed.

### 3.2 Candidate validation

The validator checks the complete record before an experiment starts:

1. Require a supported schema id, unique candidate id, valid parent and current incumbent identities, and all required artifact pins.
2. Require the parent to match the current incumbent or the explicitly named parent candidate. A stale parent is rejected; it is never rebased implicitly.
3. Require the requested owner/visibility scope to equal the execution scope supplied by the runtime. The candidate cannot choose or widen that scope.
4. Require `edit_scope` and `diffs` to match exactly and contain only the two v1 kinds above.
5. Require expected value ids to match the incumbent values and replacement ids to match the supplied structured replacement values under the approved content profile.
6. Require all referenced context and skill ids to exist in the owner-supplied pinned catalogs. No filesystem paths or unlisted references are accepted.
7. Require every requested cap to be less than or equal to the corresponding runtime-approved cap. A missing runtime cap disables probing.
8. Reject protected-field changes, unknown enum values, malformed or duplicate ids, duplicate candidate ids, missing source evidence, stale catalog pins, executable content, or an identity/profile mismatch without changing the incumbent.

The unchanged incumbent is always an eligible final selection. An invalid proposal consumes its declared proposal/validation budget, produces a refusal record, and leaves the incumbent available.

## 4. Budget profile and requested caps

```text
RequestedCaps = {
  max_k: UInt32,
  max_depth: UInt32,
  max_refinement_rounds: UInt32,
  max_candidates: UInt32,
  max_probe_executions: UInt32,
  max_concurrent_workers: UInt32,
  max_fuel: UInt64,
  max_wall_ms: UInt64,
  max_model_calls: UInt32,
  max_input_tokens: UInt64,
  max_output_tokens: UInt64,
  max_memory_bytes: UInt64,
  max_compute_units: UInt64,
  max_tool_calls: UInt32
}
```

The referenced `BudgetProfile` is runtime-owned and supplies the approved ceiling for every field. The effective limit is the lower of the requested value and the profile ceiling. Candidate values can never raise a profile ceiling or change the profile. No probe may begin when a required cap is absent or unknown.

The current MAC-3 pilot ceilings are frozen as:

- `max_k <= 2`;
- `max_depth <= 2`;
- `max_probe_executions <= 8` per task, including failed executions and retries;
- `max_concurrent_workers <= 2`.

Parallel mode must have two distinct proposals before composition. Sequential mode must have at least two refinement rounds when that mode is evaluated. Both modes remain within `max_k`, `max_depth`, the eight-probe task ceiling, and all other budget fields. Unused budget does not carry into another task. Exhaustion stops the run and retains the baseline. No automatic retry is free.

MAC-3 does not yet publish numeric ceilings for fuel, wall time, model calls, input/output tokens, memory, compute units, or tool calls. The execution owner must supply these values from existing runtime/model admission limits before enabling a probe. Until then, the only permitted behavior is baseline execution or an explicitly labelled offline fixture whose bounds are fully declared by that fixture. Do not invent values in this contract.

## 5. Probe observation and decision receipt

Each planned attempt receives an observation record, including an attempt that never starts. Completion state and verifier verdict are separate so that missing, interrupted, failed, and completed-but-unverified runs cannot be conflated.

```text
ProbeObservationV1 = {
  schema_id: SchemaId,                         // "aien.harness.probe-observation/1"
  run_id: OpaqueRef,
  attempt_id: OpaqueRef,
  attempt_index: UInt32,
  candidate_id: ContentId,
  incumbent_id: ContentId,
  task_case_ref: ContentId,
  mode: none | single_step | parallel | sequential,
  execution_state: not_started | running | completed | failed | cancelled | interrupted,
  environment_kind: deterministic_fixture | host | spark,
  worker_kind: fake_test_double | real_model,
  source_pin: ArtifactRef,
  compiler_seed_pin: ArtifactRef,
  executable_pin: ArtifactRef,
  model_pin: ArtifactRef,
  tokenizer_pin: ArtifactRef,
  policy_pin: ArtifactRef,
  fixture_pin: ArtifactRef,
  actual_use: ActualUse,
  output_artifact_refs: List<ArtifactRef>,
  verifier_ref: Option<ArtifactRef>,
  verifier_status: not_run | pass | fail | inconclusive,
  failure_code: Option<FailureCode>,
  signed_receipt_ref: Option<EvidenceRef>
}

ActualUse = {
  proposal_count: UInt32,
  probe_count: UInt32,
  retry_count: UInt32,
  model_calls: UInt32,
  input_tokens: UInt64,
  output_tokens: UInt64,
  wall_ms: UInt64,
  fuel: UInt64,
  peak_memory_bytes: UInt64,
  compute_units: UInt64,
  tool_calls: UInt32,
  energy_measurement: unmeasured | measured(EnergyObservation)
}
```

`EnergyObservation` includes the named instrument, measurement boundary, units, and receipt reference. Estimated energy cannot be reported as measured. A fake worker must carry `worker_kind=fake_test_double` and a fixture pin. It can prove a deterministic path and negative control only; it is not evidence of real-model or physical Spark qualification.

The independent verifier, not the candidate or proposer, creates the verdict and signed receipt reference. The receipt binds the source, compiler seed, executable, model/tokenizer, policy, fixtures, verifier, and relevant hardware pins. The candidate cannot read sealed final-task contents, future corrections, private grader rules, verifier keys, or answers. Receipts and output artifacts are references, not embedded private data.

`FailureCode` is a closed, versioned enum. Initial values include `invalid_candidate`, `stale_parent`, `unsupported_version`, `scope_mismatch`, `protected_edit`, `unknown_reference`, `budget_profile_missing`, `budget_exhausted`, `worker_unqualified`, `worker_unavailable`, `probe_failed`, `probe_interrupted`, `artifact_missing`, `verification_not_run`, `verification_failed`, `duplicate_attempt`, and `receipt_invalid`. Unknown failure codes are preserved as `UNRECOGNIZED_FAILURE` by reporting tools but cannot be treated as success.

A run-level decision record names the selected `candidate_id` or `incumbent_id`, all attempts, the evidence refs used for comparison, and a reason code. It must never select a candidate without an independently verified completed artifact. If all candidates fail, are missing, or are inconclusive, select the incumbent or abstain.

## 6. Lesson candidate

Only an independently verified outcome may produce a lesson candidate. A lesson is a claim until the canonical owner admits it; retrieval never grants authority.

```text
LessonCandidateV1 = {
  schema_id: SchemaId,                         // "aien.harness.lesson-candidate/1"
  lesson_id: ContentId,
  task_family: TaskFamily,
  scope: ScopeRef,
  applicability_conditions: List<ApplicabilityCondition>,
  source_task_ref: ContentId,
  source_evidence_refs: List<EvidenceRef>,
  adopted_strategy_id: ContentId,
  strategy_version: UInt32,
  specific_change: List<ComponentKind>,
  observed_result: OutcomeSummary,
  confidence: ConfidenceReport,
  resource_cost: ActualUse,
  known_failures: List<FailureCode>,
  counterexamples: List<EvidenceRef>,
  reconsider_when: List<ReconsiderCondition>,
  validity: claim | verified | admitted | revoked | contradicted | stale | superseded
}
```

`ApplicabilityCondition` and `ReconsiderCondition` are typed facts/constraints over task family, catalog revision, policy revision, evidence freshness, and declared task scope. They are not natural-language instructions. `OutcomeSummary` records verified completion, verified refusal, failure, or inconclusive result and refers to the corresponding independent evidence. `ConfidenceReport` records the estimate, its basis, uncertainty, sample count, and any calibration-profile reference; a model self-score alone is not an evidence basis.

Lesson lifecycle:

1. Allen emits `validity=claim` with source task and evidence references.
2. The independent verifier checks the referenced run and output. A verifier rejection or missing receipt blocks admission.
3. Omega Cortex receives a typed candidate through its existing single writer. Only the Cortex owner applies its existing evidence-linked promotion policy.
4. Skill changes, if any are separately accepted, go through the existing skill ledger and rollback owner. A lesson cannot write a skill.
5. Retrieval is scope-filtered and read-only. Revoked, contradicted, stale, corrupt, or scope-mismatched lessons are refused. A changed task intent or changed required catalog/model/policy pin invalidates reuse until reconsidered.
6. Revocation or correction is a new linked record under the owning memory policy; no old record is overwritten.

Private operator lessons stay on the owner's machine and are never visible to public/anonymous sessions. Public visitor conversations are not training sources by default. No lesson or candidate may contain a secret, raw trace, raw conversation, tool credential, evaluation answer, or unapproved source material.

## 7. Protected immutable scope

The optimizer may not edit, weaken, replace, derive, or self-approve changes to:

- Allen's identity, SubjectState, identity-to-memory binding, or model-generation identity;
- user/tenant/session scope, public/private classification, consent, retention, or deletion policy;
- capability grants, AEGIS policy, approval decisions, execution authority, tool/network/filesystem scope, or effect ceilings;
- trusted system prompts, hard guardrails, policy text, evaluator code, rubric, sealed tasks/answers, evaluator keys, or receipt signer;
- the candidate schema, content-id profile, budget profile, model admission manifest, worker qualification, skill catalog, or runtime contract;
- executable code, shell commands, scripts, hooks, plugins, middleware, compiler/runtime code, skill bodies, secrets, release/deployment controls, model weights, or promotion authorization.

Protected values may be referenced by an opaque pinned id for validation. They are not candidate-editable payloads. Any attempt to represent a protected change is rejected before probing, counted against the experiment, and recorded without changing the incumbent.

## 8. Compatibility, refusal, and recovery

- The `/1` schema ids define major version 1. Unknown major versions, enum values, component kinds, required fields, digest profiles, and incompatible catalog/policy pins are rejected before work begins.
- A minor revision may add only optional, non-authoritative descriptive fields. A consumer that does not recognize such a field may ignore it only if the field is outside scope, permission, budget, identity, content identity, evidence, and verification. Unknown fields in those protected domains cause refusal.
- Existing records are immutable. A correction, invalidation, revocation, or superseding interpretation creates a new record linked to the prior content id. Never rewrite a record whose id is already referenced by a receipt.
- Duplicate candidate ids, duplicate attempt ids, stale manifests, missing receipts, corrupt content ids, or an interrupted run cannot be resumed as completed. Resume requires the existing execution owner's durable journal to confirm the same run, remaining budget, pins, and idempotency state. Otherwise mark interrupted and start a new bounded run with a new id.
- The unchanged incumbent is retained after all refusal, crash, timeout, cancellation, resource-exhaustion, or verification-failure paths. External effects are not retried by this contract.

Initial refusal codes: `unsupported_version`, `unknown_field`, `invalid_content_id`, `duplicate_candidate`, `duplicate_attempt`, `stale_parent`, `scope_mismatch`, `edit_scope_mismatch`, `protected_edit`, `unreviewed_executable`, `unknown_context_ref`, `unknown_skill_id`, `catalog_mismatch`, `budget_profile_missing`, `budget_exceeded`, `worker_unqualified`, `evidence_missing`, `receipt_invalid`, `lesson_revoked`, `lesson_contradicted`, and `recovery_state_unproven`.

## 9. Activation and selection rules

1. Default mode is `disabled`. A local `shadow` mode may record proposals and run only the separately authorized deterministic/offline fixture. It cannot change the user-visible answer, invoke a new tool, commit an effect, write a skill, write/promote Cortex, select an unqualified worker, or change model weights.
2. Until MAC-1 through MAC-8 have candidate-bound evidence and independent review, live task selection remains the existing baseline. An offline pilot may compare candidate and base in isolation; no candidate is installed as incumbent.
3. A user-facing route remains subject to the existing Core #735 admission validator. Worker availability, model/checkpoint/tokenizer/backend qualification, privacy, capability, budget, and resource pressure are checked independently at dispatch time. Worker output returns to Allen as untrusted task data.
4. Any later production strategy activation is a separate gate. It requires a predeclared positive net improvement on fresh sealed real-model tasks, no material correctness/safety regression, independent signed review, and explicit operator authorization. A contract, branch, host fixture, fake worker, or MAC pass alone does not authorize activation.
5. The private 35B process stays untouched; the 27B public route stays disabled until its separate qualification and release gates pass. No public session may access private operator lessons.

## 10. Known interface blockers before implementation

These are deliberate unresolved owner interfaces, not permission to invent substitutes:

1. **Content identity profile:** Omega must identify the current canonical content-id/semantic-id encoding for candidate and diff payloads and provide conformance vectors. Allen uses the opaque `ContentId` shape above; no duplicate hash format is introduced here.
2. **Runtime budget profile:** Core/Omega admission owners must publish the concrete ceilings for fuel, wall time, model calls, tokens, memory, compute units, and tool calls. MAC-3 fixes `k`, probe-execution, and concurrency ceilings only. Missing ceilings disable probing.
3. **Probe and verification handoff:** Core's Spark Harness and Spark RSI must identify the exact existing request/result/receipt types that carry `ProbeObservationV1` fields. This contract does not create another runner, durable journal, judge, or signer.
4. **Lesson admission/retrieval:** Omega Cortex and skill-ledger owners must map `LessonCandidateV1` to their current typed candidate/evidence and scope interfaces. Allen cannot write their journals or decide promotion.
5. **Wire encoding:** if an inter-repository or network message is required, aien-protocols must select/reuse the transport record. This document alone does not authorize a new wire format.
6. **Worker conversation and Responses API:** Core #735 owns per-request worker admission and dispatch; Core #736 owns complete native Responses API support in the local model service. Allen must use the admitted client path after both owners publish compatible interfaces. The 35B endpoint currently has only operator-reported Chat Completions support; the 27B endpoint, API surface, capabilities, and availability remain unverified. No second adapter, server, or model route is introduced here. The intended complementary worker roles and bounded conversation shape are recorded in `docs/WORKER_COLLABORATION.md`; they are proposals pending exact worker qualification, and agreement between models does not count as independent verification.

These blockers do not prevent freezing the logical schema in Allen. They do prevent claiming MAC implementation, qualified probe execution, lesson admission, or activation until the named owners supply and verify their sides of the contract.

## 11. Acceptance mapping

| MAC gate | Contract coverage | Remaining proof |
|---|---|---|
| MAC-1 | Identifies the `.om` runtime as consumer and keeps this document non-executable. | Actual seeded `.om` parse/validate/execute path and Allen entry-point integration. |
| MAC-2 | Candidate v1, content identity, two editable component kinds, parent/version/scope validation and protected fields. | Producer/consumer implementation; valid, malformed, unknown-version and stale-parent tests. |
| MAC-3 | Bounded modes, frozen `k`/probe/concurrency ceilings, baseline selection and budget ledger fields. | Numeric runtime caps and independently enforced parallel/sequential execution. |
| MAC-4 | Immutable security scope, refusal codes, no executable content, scope and receipt boundaries. | Required negative controls and mutants against actual execution. |
| MAC-5 | Lesson candidate shape, evidence-linked lifecycle, revocation and scope rules. | Existing Cortex/skill-ledger integration and restart/reuse test. |
| MAC-6 | Task families, task/evidence references, observation fields, sealed-evaluation boundary and cost fields. | At least 30 frozen tasks, pre-registered comparison, RSI #67 isolation and independent scoring. |
| MAC-7 | Candidate/run/artifact/compiler/model/fixture/receipt references and restart states. | Runnable offline E2E and actual independently checked receipt. |
| MAC-8 | Disabled/shadow defaults, existing admission, no public lesson crossover or auto-promotion. | Runtime configuration proof and activation/refusal negative controls. |

**This contract is not evidence that any MAC gate has passed.** Its status remains PROPOSED / NOT_RUN until a candidate implementation consumes it and the owning reviewers accept the evidence.
