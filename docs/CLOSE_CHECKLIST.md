# Programme close checklist

The Allen programme issue ([aien-dev/allen#1](https://github.com/aien-dev/allen/issues/1)) closes only when two things are true:

1. The **programme close guard** (`allen-guard close-check`, policy in `guard/policy.toml`) returns `accepted` on live issues.
2. Every **manual item** below is signed, because no machine check covers it.

The guard is necessary, not sufficient. An accepted verdict with an unsigned manual item is still not a closable programme.

## What the guard checks by machine

For the programme issue, the eight phase issues P0 to P7 (allen#2 to allen#9) and the 21 mandatory external prerequisites listed in `docs/PHASES.md` (copied into `guard/policy.toml`; a test fails if the two drift apart), an issue is **accepted** when:

- it is closed with the reason "completed" (not "not planned", not a duplicate, not closed without a reason);
- its body has no unchecked task-list box (`- [ ]`) anywhere;
- no status line of its body (a line containing `Status:` or `qualification:`) carries a forbidden marker: `qualification: NOT_RUN` or `Status: PROPOSED`.

The programme issue itself is not required to be closed (closing it is what triggers the guard), but its own checklist must be complete and its status line clean.

An issue the guard cannot read is a blocker ("not fetched"), never a pass.

**Waivers.** A prerequisite labelled `allen-guard:waived` skips the two body checks (boxes and markers). It must still be closed as completed, and the guard lists every waiver in its comment. A waiver label on a phase or on the programme is ignored and reported as ignored: phases cannot be waived.

## Manual items (no machine check covers these)

Sign each line with who, when (UTC date) and a link to the evidence. A line with no link is not signed.

| # | Item | Signed by | Date (UTC) | Evidence link |
|---|---|---|---|---|
| M1 | Independent review of the frozen scope and of every phase's evidence, by a reviewer on a **different model** than the author of that evidence (record both model ids). | | | |
| M2 | Drake's explicit yes to closing the programme, in his words, linked. | | | |
| M3 | Every scope-freeze amendment since the B0 acceptance contract was frozen has its own review and new acceptance tests (or the line says "no amendments"). | | | |
| M4 | Cross-repository prerequisites whose evidence lives in receipts (aien-dev/aien-receipts) rather than in the issue body: each receipt read and linked here, with its digest. | | | |
| M5 | The guard's latest live verdict is `accepted` and its run URL is linked here. | | | |

## Admin bypass, said plainly

GitHub lets a repository administrator remove or bypass automation: disable the workflow, edit it, delete the policy, or close the issue in a way the workflow does not see. No issue template or ordinary workflow can promise that a privileged owner is physically unable to override it.

What the guard does promise: under its installed policy, it reliably catches a premature closure of the programme issue and undoes it (reopens the issue and comments the remaining blockers with the run URL). If the guard itself fails before it can decide, it reopens anyway.

Any override is recorded in the audit trail: the guard's comment on the programme issue, plus a line in the override table below. **An override never counts as passing.** It is a recorded decision to close without the gate, not evidence that the gate was met.

### Override table

| Date (UTC) | Who | What was overridden (issue, workflow, policy) | Why | Guard run or comment link |
|---|---|---|---|---|
| | | | | |

## How to run the guard by hand

From the repository root, with `gh auth login` done (any account that can read the listed repositories):

```sh
cargo build --release -p allen-guard

# Live: read every policy issue through gh api, save what was read, print the verdict.
./target/release/allen-guard close-check --policy guard/policy.toml --live \
  --write-snapshot evidence-snapshot.json --markdown verdict.md > verdict.json
echo "exit $?"   # 0 accepted, 2 not accepted, 3 some issue could not be read, 1 error

# Re-evaluate a saved snapshot (no network).
./target/release/allen-guard close-check --policy guard/policy.toml --snapshot evidence-snapshot.json
```

On GitHub: Actions, `programme-close-guard`, "Run workflow". Leave `dry_run` ticked to only evaluate (the snapshot and verdict are attached to the run as artifacts). Untick it to also reopen the programme if it is closed and not accepted.

The source-control guard runs the same way: `./target/release/allen-guard scan` (whole checkout), and `scripts/install-hooks.sh` installs it as a pre-commit hook.

## How to read the guard's comment

The comment on the programme issue starts with one of:

- **"Programme close guard: not accepted"**: the issue was reopened (or left open). The table lists every blocker: the issue, its role (phase or prerequisite), the phase name or prerequisite area, and the reason. Reasons are one of: `open`; `closed as not_planned, not completed` (or another close reason); `closed without state_reason completed`; `N unchecked task-list item(s)`; `status line carries forbidden marker ...`; `not fetched`. Fix each one in the named issue, then close the programme again.
- **"Programme close guard: accepted"**: every machine check passed and the closure stands. The manual items above still have to be signed.
- **"Programme close guard: could not evaluate"**: the guard failed before deciding; the closure was undone. Open the run link to see why.

Every comment ends with the run URL. The comment never quotes issue text, only references, reasons and policy markers.
