# Phase ledger

Programme issue: [aien-dev/allen#1](https://github.com/aien-dev/allen/issues/1) (transferred 2026-10-20 from aien-architecture-mv#278; the old URL redirects, comments and history preserved).

Phase numbers are sequence, not priority. Progress status words: PROPOSED, SCOPED, ACTIVE, IN_REVIEW, COMPLETE. Qualification verdicts are separate: PASS, FAIL, INCONCLUSIVE, NOT_RUN. A phase closes only with its acceptance evidence; the programme close guard (`guard/`) reopens the programme otherwise.

| Phase | Issue here | Former issue | Title | Status | Qualification |
|---|---|---|---|---|---|
| P0 | [#2](https://github.com/aien-dev/allen/issues/2) | arch#279 | Establish Allen's own repository, mission and B0 acceptance contract | ACTIVE (2026-10-20) | NOT_RUN |
| P1 | [#3](https://github.com/aien-dev/allen/issues/3) | arch#280 | Build reproducible training episodes from the existing conversation archive | PROPOSED | NOT_RUN |
| P2 | [#4](https://github.com/aien-dev/allen/issues/4) | arch#281 | Label human intent, corrections, successes and failures with evidence | PROPOSED | NOT_RUN |
| P3 | [#5](https://github.com/aien-dev/allen/issues/5) | arch#282 | Freeze leakage-resistant evaluations and measure the baseline | PROPOSED | NOT_RUN |
| P4 | [#6](https://github.com/aien-dev/allen/issues/6) | arch#283 | Train and compare a bounded first personal Allen candidate | PROPOSED | NOT_RUN |
| P5 | [#7](https://github.com/aien-dev/allen/issues/7) | arch#284 | Qualify Allen B0 through one complete personal-assistance experience | PROPOSED | NOT_RUN |
| P6 | [#8](https://github.com/aien-dev/allen/issues/8) | arch#285 | Keep one Allen continuous across iMac, Pi, Spark and MacBook | PROPOSED | NOT_RUN |
| P7 | [#9](https://github.com/aien-dev/allen/issues/9) | arch#286 | Learn continually and anticipate useful help under bounded exploration | PROPOSED | NOT_RUN |

Order: P0 -> P1 -> P2 -> P3 -> P4 -> P5 produces B0 only if its gates pass; P6 extends continuity to the four devices; P7 adds evaluated continual learning. P3's evaluation schema may be drafted during P1/P2, but evaluation data is isolated before any fitting, retrieval indexing or preference extraction.

## Mandatory external prerequisites (programme cannot close while any is open)

Verified OPEN when the gate was written (2026-10-20). The close guard reads this list from `guard/policy.toml`; keep both in step.

| Area | Issues |
|---|---|
| Identity, persona, experience, release | aien-architecture-mv #159, #269, #190 |
| Physical Pi to Spark execution and independent acceptance | aien-architecture-mv #231, #232; aienos-mv #396, #398, #399; aien-protocols-mv #27; aien-sovereign-core-mv #586; omega-mv #505; aegis-runtime-mv #53 |
| Native Spark model path | aienos-mv #286, #327 (evaluated under aien-architecture-mv #190) |
| Learning economics and out-of-sample evidence | aien-architecture-mv #246, #262, #263, #276; omega-mv #583, #584, #600 |

P6 owns the remaining iMac and MacBook physical qualification if no existing issue owns it.
