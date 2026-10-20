# Evidence: stream `guards` (ledger L177)

Allen P0 acceptance item: "Raw logs, weights and secrets cannot accidentally enter source control", plus the required programme close guard. Crate `allen-guard` in `guard/`.

Status: IN_REVIEW (pushed on `guards/v0`, not merged). Qualification of what ran is listed per item below; nothing here claims more than the named run.

## Local checks (MacBook, rustc 1.97.1, aarch64 macOS)

| Check | Result | File |
|---|---|---|
| `cargo test --locked` | PASS: 41 tests, 0 failed | `cargo-test.txt` |
| `cargo clippy --locked --all-targets -- -D warnings` | PASS: exit 0, no warnings | `clippy.txt` |
| `cargo fmt --all --check` | PASS: exit 0 | `clippy.txt` |
| `allen-guard scan` over the checkout | PASS: 0 findings (fixtures allowlisted by `guard/scan.toml`) | CI logs below |
| Mutants on the close predicate and scan rules | 6 of 6 caught | `mutants.txt` |

The first local test run had 2 failures before the fixes in commit 0692055 (absolute paths judged by the forbidden-directory rule; hook output read from the wrong stream). A later test caught a real gap in `scripts/scan-history.sh` (an invalid commit range scanned nothing and passed); fixed in f229270.

## GitHub Actions runs on `guards/v0`

| Workflow | Event | Commit | Conclusion | Run |
|---|---|---|---|---|
| guard | push | f229270 | success | https://github.com/aien-dev/allen/actions/runs/39426382156 |
| programme-close-guard | push (dry run) | f229270 | success | https://github.com/aien-dev/allen/actions/runs/39426382228 |
| guard | push | 9ff6fff | success | https://github.com/aien-dev/allen/actions/runs/39426651493 |
| programme-close-guard | workflow_dispatch, dry_run=true | 9ff6fff | success | https://github.com/aien-dev/allen/actions/runs/39426651400 |

The `guard` run on f229270 ran 41 tests on ubuntu-latest, scanned 62 files of the checkout with 0 findings, and scanned the pushed commit range 0692055..f229270 with 0 findings (run log).

## Live dry run (2026-10-20, run 39426651400)

Files from the run's artifact, unchanged:

- `live-dry-run-snapshot.json`: the 30 issues as `gh api` returned them with the workflow's `GITHUB_TOKEN` (sha256 a7e88fb535b518c1779048b6e9c2bbedebfd95dc44a279a169591e3315332267).
- `live-dry-run-verdict.json` (sha256 c4428a950dd30394022b91c7de3ea08b48181d422832d71e1098699c41434293) and `live-dry-run-verdict.md` (the comment the guard would post).
- Policy evaluated: `guard/policy.toml`, sha256 3e7fd02651d7fe20610f258ac7d03c012c09f446b96671d00544c52632452d75.

Result: **not accepted**, which is the expected and correct result today. All 30 required issues were read (0 fetch errors); all 30 are open (snapshot `state` field). 73 blockers: 29 "open" (every phase and prerequisite; the programme's own state is not a blocker), 18 issues with unchecked task-list items, 13 with `Status: PROPOSED` and 13 with `qualification: NOT_RUN` on a status line (verdict file). Mode was dry-run: no issue was reopened or commented.

Re-evaluating the saved snapshot offline (`allen-guard close-check --policy guard/policy.toml --snapshot live-dry-run-snapshot.json`) exits 2 and produces a verdict identical to the run's (checked with `jq -S` and `diff`).

## Not verified

- The `issues: closed` trigger has not fired against the real programme issue: GitHub runs issue-event workflows from the default branch, so it can only fire after `guards/v0` is merged to `main`. The reopen-and-comment step has therefore NOT_RUN on GitHub; its logic is covered only by reading and by the local CLI tests of the verdict it consumes.
- The pre-commit hook is tested in a throwaway repository (`guard/tests/cli.rs`) and was active for this stream's own commits on the MacBook; it is not installed in any other clone.
- Admin bypass is documented in `docs/CLOSE_CHECKLIST.md`, not prevented (it cannot be).
