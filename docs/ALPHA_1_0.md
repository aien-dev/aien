# Allen Alpha 1.0 delivery status

2026-10-23. Progress: ACTIVE. Interactive release qualification: NOT_RUN.

Drake requested completion of Allen Alpha 1.0 alongside Omega `.om` and explicitly
authorized public visibility. Allen and its pinned Omega compiler repository
are public; unauthenticated GitHub API reads verified both on this date.
No downloadable interactive alpha or physical iMac qualification is claimed.

## Existing implementation, one shared core

The handwritten seeded Omega application remains in the existing platform owner:
[Allen native core](https://github.com/aien-dev/aienos-mv/tree/f52f17a9e9520c1d16ba4d30aa8ee3bda8ee12a5/native/omega/allen).
Its [delivery contract](https://github.com/aien-dev/aienos-mv/blob/f52f17a9e9520c1d16ba4d30aa8ee3bda8ee12a5/native/omega/allen/ALPHA.md)
requires separately qualified native iMac boot and a free temporary hosted
visual app, with local inference first-class and remote inference optional.
This repository does not create a second identity, memory store or runtime.

The [portable build candidate](https://github.com/aien-dev/aienos-mv/commit/bd4f713)
removes a private compiler-folder dependency while retaining the exact compiler
digest. The [source-only compiler](https://github.com/aien-dev/omega-bridge/tree/0fc7d8662cb799e7c206b17c18ea4c3ec2b8fea9)
can now be acquired without signing in. Its anonymous download and seed rebuild
passed; the complete Allen native component gate passed from a clean source
export, including 24 compiled fault controls. These are Linux AArch64 results.
See the candidate's `evidence/allen-portable-build-20261023/` for raw receipts.
Candidate work is proposed until integrated through the existing publication desk.

## Remaining release requirements

| Requirement | Current evidence and owner |
|---|---|
| Public source acquisition | PASS: Allen and omega-bridge public, anonymous reads and compiler download verified |
| Reproducible seeded component build | PASS on candidate above; independent review and integration pending |
| Real visual window, keyboard and input loop | NOT_RUN; existing Allen platform owner |
| Live conversation plus durable session restore | NOT_RUN for this visual artifact; reuse existing gateway/storage owners |
| Qualified hosted iMac executable | NOT_RUN; existing Omega compiler/platform owners, no foreign implementation fallback |
| Qualified native iMac boot and device path | NOT_RUN; emulator acceptance then bundled physical trial |
| Source/license/checksum bundle and recovery/uninstall instructions | No qualified interactive artifact to package yet |
| Fresh-user/non-Spark acquisition and real interaction | NOT_RUN |

Public source availability does not close B0 or P0 through P7. Their existing
acceptance contracts, authority boundaries and evidence requirements remain.
The application may be called a public alpha only after its supported acquisition
and interactive launch path passes. Unsupported platforms must be named explicitly.
