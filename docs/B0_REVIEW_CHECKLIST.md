# B0 acceptance contract: review checklist

Status: PROPOSED. Used by the reviewers named in `docs/B0_ACCEPTANCE_CONTRACT.md` section 10.1. A reviewer copies this list into `evidence/contract/REVIEW-<date>.md`, marks each line PASS, FAIL or NOT_CHECKED, and gives the line or source for every FAIL. NOT_CHECKED is not PASS.

Contract commit reviewed: `<sha>`. Reviewer model: `<model>` (must differ from the author's). Date: `<UTC date>`.

## Consistency with owners

- [ ] No contradiction with the acceptance sections of aien-dev/allen#3 to #9 (P1 to P7).
- [ ] No contradiction with allen#1 (programme) and allen#2 (P0) acceptance.
- [ ] Identity: no new identity, no `AllenId`, SubjectState untouched (ADR 0035 section 3, I3, I8).
- [ ] Memory: Cortex (ADR 0022) and `aien-allen-memory` (ADR 0036) keep ownership; nothing here creates a store.
- [ ] Authority: every effect goes through S4 `authorize` and S5 `execute`; approval floors (aien-sovereign-core-mv#667) and the operator deny list outrank the section 5.2 table; profile never grants permission (`CONTRACT-v1.md` section 5).
- [ ] Multi-device: nothing pre-empts P6 (allen#8); one writer to SubjectState.
- [ ] Sequencing: nothing claims authority that `CURRENT_EXECUTION_PLAN.md` holds.

## Testability

- [ ] Every gate in section 3 can produce PASS, FAIL, INCONCLUSIVE and NOT_RUN, and says when each applies.
- [ ] Every human-effort measure names its log and who records it.
- [ ] The restart gate names the digests and has a negative control.
- [ ] Both negative controls (C1, C2) are defined and the consequence of either passing is stated.
- [ ] No numeric threshold appears without a source; every needed number points to `evidence/p3/B0_PREREG.toml`.
- [ ] Every item in section 11 names the measurement that decides it and who runs it; none is phrased as a question to Drake.

## Privacy

- [ ] The contract contains no message text, sample, credential or weight.
- [ ] Section 6 says what leaves the Spark, and it is counts, digests, fixtures and scores only.
- [ ] Deletion and export ownership is named for every data class (section 6.1).
- [ ] The CONTAMINATED checkpoint rule (section 5.3) covers retire and retrain.

## Plain language

- [ ] Plain English, short sentences, no em dashes or en dashes.
- [ ] Every number names its source.

## Verdict

Reviewer verdict: `<PASS | FAIL>`, with the list of FAIL lines. Drake's yes is recorded separately (contract section 10.1).
