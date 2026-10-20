# Access-controlled source manifest

The manifest lists every conversation source file Allen P1 may read. It is **not in git** and holds one row per file.

| Item | Value |
|---|---|
| Location | `~/archive/agent-chats/manifests/2026-10-20-source-manifest.tsv` on the Spark (directory mode 0700, file mode 0600) |
| Rows | 16,144 (plus one header line) |
| Its own sha256 | `2ad87ff8281d7cc3a29cddbad5f572c646453f95cb21211eb7178494b5dc70b2` |
| Columns | host, agent, path, bytes, mtime_utc, sha256 |
| Generated | 2026-10-20 12:50Z to 12:52Z |
| Regenerate | `inventory/gen-manifest.sh 2026-10-20` (writes `<date>-source-manifest.tsv`; re-running with the same date replaces that day's file) |

Rows by host and agent (from `awk` over the manifest; counts only):

| Host label | Rows | Bytes |
|---|---|---|
| spark-archive (archive raw/ and records/ trees) | claude 3,402, codex 491, gemini 1,344, muse 83, opencode 14 | 9,259,048,798 |
| spark (original sources) | claude 6,899, codex 465, gemini 718, muse 526, opencode 3, hermes 2 | 5,446,792,518 |
| macbook (originals over read-only ssh) | claude 164, codex 984, gemini 1,037, hermes 6, opencode 3, catalog 3 | 9,386,645,042 |

Every row has a sha256 (0 rows marked not-hashed); the MacBook hashed quickly with `shasum -a 256`.
Live files (current Claude chats, live databases, the growing raw mirror) are hashed at the moment of reading, so a later read can differ; the manifest records what was read at that time. The Mac step ran fine; if the Mac is asleep the script writes the Spark rows and prints `mac step: NOT_RUN` instead of guessing.

## Who may read it
Drake, and processes running under his Spark account. The file mode keeps other accounts out. No other agent or service gets a copy; no row may be copied into a PR, issue, CI log, ledger note or handoff (counts and the file's own digest only).

## Deletion and export owner
- Drake owns every deletion and export decision.
- `aien-dev/agent-archive` is the implementation owner: it holds the raw mirror and records that deletion has to act on.
- A deletion must also be propagated to every derived dataset or trained artifact built from the deleted source. Allen P1 (episodes) and P4 (training) record which sources each derived artifact used, by manifest sha256, so a deletion can find them.
- Deleting a source does not edit this manifest; a new dated manifest is generated and the old one is kept until Drake decides otherwise.
