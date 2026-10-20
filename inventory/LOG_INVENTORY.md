# Allen P0: conversation log inventory (L175)

Status: ACTIVE. Qualification: NOT_RUN (this is a count, not a test).
Counted on 2026-10-20 between 12:40Z and 13:10Z on the Spark, with read-only `ssh macbook` for the MacBook.
Every number comes from a script in this directory; the exact commands are in `COMMANDS.md`, raw script output is in `data/`.
Privacy: counts, sizes, dates, hosts, paths, session ids and digests only. No message text appears here.

The archive is live (new Claude records arrive every few minutes), so counts of the live agent move by a few records between runs.
Where two numbers for one thing differ, both are shown with the command that produced each. Known live drift: Mac Claude jsonl bytes were 128,082,362 on my first ad hoc count and 128,502,825 in `data/mac-inventory.txt` (the Mac chat kept writing); I use the second.

## 0. Plain-English summary (for Drake)

Allen's archive holds **69,061 messages from 4,429 conversations** (Claude Code, Codex, Gemini, OpenCode, Muse), dated **2026-09-05 to 2026-10-20**, all stored on the Spark. Full message text is kept (the 8,000-character cut applies only to a read-only preview file).
The archive does **not** hold everything that exists. The MacBook still has about **1,446 more conversations that were never copied**: 982 Codex sessions (July 27 to September 29, 3.95 GB), 73 Claude Code files, 161 OpenCode sessions (August 21 to September 25) and 227 Hermes sessions (October 18 to 20). The Spark's own Hermes has 3 more. Hermes has no collector at all, so none of the 230 Hermes sessions on the Mac or the 3 on the Spark are in the archive. Only Gemini is pulled from the MacBook.
The archive's text records leave out tool work (commands run, files read, results); that evidence survives only in the raw copies for Claude and Codex (about 210,000 Claude tool calls, about 9,500 Codex tool calls) and is missing for OpenCode (5,905 tool parts exist in the Spark database, not copied) and for every Mac source that is not mirrored. The oldest conversation anywhere is a Codex file on the MacBook from 2026-07-27, two months before the archive starts.

## 1a. Archive records per agent (`~/archive/agent-chats/records/`)

Snapshot: `data/spark-inventory.txt`, section 1a. Record "days" means one file per UTC date.

| Agent | Day files | First record date | Last record date | Records | Bytes | user | assistant | system | tool | Sessions (distinct ids) | Hosts |
|---|---|---|---|---|---|---|---|---|---|---|---|
| claude | 28 | 2026-09-23 | 2026-10-20 | 55,980 | 84,395,592 | 15,324 | 40,656 | 0 | 0 | 3,235 | spark 55,980 |
| codex | 26 | 2026-09-05 | 2026-10-18 | 4,632 | 17,534,942 | 1,201 | 2,097 | 1,334 | 0 | 464 | spark 4,632 |
| gemini | 20 | 2026-09-16 | 2026-10-18 | 7,019 | 10,700,683 | 1,850 | 5,169 | 0 | 0 | 585 | macbook 5,985, spark 1,034 |
| muse | 2 | 2026-09-20 | 2026-10-04 | 71 | 30,658 | 38 | 33 | 0 | 0 | 38 | spark 71 |
| opencode | 13 | 2026-09-17 | 2026-10-02 | 1,359 | 1,389,198 | 316 | 1,043 | 0 | 0 | 107 | spark 1,359 |
| all | | 2026-09-05 | 2026-10-20 | 69,061 | 114,051,073 | 18,229 | 49,000 | 1,334 | 0 | 4,429 | |

Totals are shell arithmetic over the rows above (69,061 records, 4,429 sessions). The record schema has no `tool` role; roles are only user, assistant, system. The Codex `system` role is the Codex "developer" role mapped to system by the parser.
Counts: `agent-archive status` shows today/total per agent and agrees with the file counts above for claude, codex, opencode, muse (55,972 vs 55,980 for claude only because the archive grew between my first and second run; the first jq count was 55,972 and the second 55,980, both from `cat records/claude/*.jsonl | wc -l`).

## 1b. Raw mirror per agent and host (`~/archive/agent-chats/raw/<agent>/<host>/`)

mtime here is when the collector wrote the mirror file, so "oldest mtime 2026-10-04" is the day the collector first ran, not the date of the conversation.

| Agent/host | Files | Bytes | Oldest mtime | Newest mtime |
|---|---|---|---|---|
| claude/spark | 3,374 | 4,164,899,228 | 2026-10-04 | 2026-10-20 |
| codex/spark | 465 | 407,371,838 | 2026-10-04 | 2026-10-18 |
| gemini/macbook | 1,081 | 3,964,196,872 | 2026-10-04 | 2026-10-18 |
| gemini/spark | 243 | 592,084,988 | 2026-10-04 | 2026-10-13 |
| muse/spark | 81 | 14,613,744 | 2026-10-04 | 2026-10-04 |
| opencode/spark | 1 | 1,978,678 | 2026-10-04 | 2026-10-04 |
| total | 5,245 | 9,145,145,348 | | |

There is no raw/claude/macbook, raw/codex/macbook, raw/opencode/macbook or raw/hermes anywhere.
Gemini mirror contents: macbook has antigravity 337 db + 337 wal + 337 shm, antigravity-cli 23 db + 23 wal + 23 shm + 1 history file; spark has antigravity-cli 239 db + 3 wal + 1 history file.

Tool evidence in the raw JSONL, lines containing the pattern (`grep -c -h -F`, counts only; one line can hold one event):

| Raw tree | JSONL lines | tool_use | tool_result | function_call | function_call_output | custom_tool_call | custom_tool_call_output |
|---|---|---|---|---|---|---|---|
| claude/spark | 1,287,277 | 210,397 | 209,165 | 0 | 0 | 0 | 0 |
| codex/spark | 79,986 | 0 | 0 | 578 | 577 | 8,950 | 8,949 |
| muse/spark | 8,279 | 0 | 0 | 0 | 0 | 0 | 0 |
| opencode/spark | 1,363 | 0 | 0 | 0 | 0 | 0 | 0 |

Muse uses its own event names: 390 raw lines have a `payload_type` containing "tool" (195 tool_batch.effect.started, 195 tool_batch.effect.terminal), so Muse tool evidence is in raw. The OpenCode mirror is one file of text parts only (1,363 lines, no tool parts); the live OpenCode database holds 5,905 tool parts that are not mirrored (1c).
Codex counts by the `jq` method in my first pass (payload type field) were 573 function_call and 8,934 custom_tool_call; the grep method above counts lines containing the pattern anywhere (including nested). Both are in the logs; I use the grep numbers.
Conclusion: Claude and Codex tool evidence exists in raw and not in records. The records hold text only. For Claude, 3,524 non-JSONL files in `~/.claude/projects` (2,655 subagent files, 574 tool-results files, plus others) are not mirrored at all.

## 1c. Original sources on the Spark (outside the archive)

| Source | Files / rows | Bytes | Oldest | Newest | In archive? |
|---|---|---|---|---|---|
| ~/.claude/projects (174 project dirs) | 3,375 jsonl (679 top-level + 2,696 under subagents) + 3,524 other files | 4,164,967,719 (jsonl) | 2026-09-23 | 2026-10-20 | jsonl yes; other files no |
| ~/.codex/sessions | 465 jsonl | 407,371,838 | 2026-09-05 | 2026-10-18 | yes |
| ~/.codex/archived_sessions | 0 | 0 | | | n/a |
| ~/.local/share/opencode/opencode.db | 107 sessions, 3,236 messages, 14,639 parts (5,905 tool, 2,830 step-start, 2,797 step-finish, 1,684 reasoning, 1,363 text, 36 compaction, 23 patch, 1 subtask), 54,594 events | 190,869,504 | 2026-09-17 | 2026-10-02 | text parts only |
| ~/.gemini/antigravity-cli/conversations | 239 db, 239 wal (all empty), 239 shm | 564,371,456 | 2026-09-23 | 2026-10-16 | db yes; wal 3 of 239 |
| ~/.gemini/antigravity (conversations dir) | none on the Spark | 0 | | | n/a |
| ~/.gemini/antigravity-ide/conversations | none | 0 | | | n/a |
| ~/.local/share/muse | 81 session.jsonl | 21,530,552 (whole tree) | 2026-09-20 | 2026-10-04 | yes |
| ~/.hermes (Spark) | state.db: 3 sessions, 37 messages (18 assistant, 15 tool, 4 user); sessions/ folder empty | 2.1 GB whole tree, state.db 753,664 | 2026-10-20 | 2026-10-20 | no collector |

Top Claude project folders by bytes (full list in `data/spark-claude-projects.tsv`, 174 rows): home 2,559 jsonl 3.20 GB (2026-09-23 to 2026-10-20); aien-dev 187, 242 MB (10-12 to 10-16); odysseus 129, 151 MB (10-13 to 10-14); omega 60, 84 MB (10-14 to 10-16); aien-sovereign-core 26, 56 MB; t3-projects-synapse 56, 53 MB; t3-projects-research 37, 50 MB; aienix 14, 24 MB. 8 project folders hold zero jsonl.

Compared against the archive cursors (`state/<agent>.json`, `data/spark-inventory.txt` section 1e):
- claude: 3,375 cursors, 3,375 source files, 0 sources without a cursor, 0 cursors without a source, 0 unread bytes. Fully caught up at run time.
- codex: 465 cursors, 465 sources, 0 unread bytes.
- gemini: 1,924 cursor keys in total (several keys per database file, so not a file count); all 239 Spark databases and all 360 Mac databases (337 + 23) are in the raw mirror. The Spark WAL files are all zero bytes, so nothing is waiting in them.
- opencode: one cursor (parts, up to the newest text part). Source text parts 1,363, mirror lines 1,363, records 1,359; the 4-row difference is not explained (cause UNVERIFIED; need the parser's skip rules).
- muse: 81 cursors, 81 source session files, 81 mirrored (38 sessions have records; 43 of 81 files are subagent logs).
- Spark Hermes: no cursor, no collector.

## 1d. MacBook sources (`ssh macbook`, read only; `data/mac-inventory.txt`)

All steps ran; ssh worked (Macbook.local). No NOT_RUN steps.

| Source | Files / rows | Bytes | Oldest | Newest | Mirrored in archive? |
|---|---|---|---|---|---|
| ~/.claude/projects (12 dirs, 9 with jsonl) | 73 jsonl + 91 other files | 128,502,825 | 2026-09-24 | 2026-10-20 | NO |
| ~/.codex/sessions | 982 jsonl (2026/07: 179, 2026/08: 678, 2026/09: 125) + 2 in archived_sessions | 3,950,080,013 | 2026-07-27 | 2026-09-29 | NO |
| ~/.gemini/antigravity/conversations | 337 db, 316 wal (0 bytes), 316 shm | 3,833,888,768 (db) | 2026-09-16 | 2026-10-14 | YES (raw/gemini/macbook) |
| ~/.gemini/antigravity-cli/conversations | 23 db, 22 wal (0 bytes), 22 shm | 114,266,112 (db) | 2026-09-16 | 2026-10-18 | YES |
| ~/.gemini/antigravity-ide/conversations | none | 0 | | | n/a |
| ~/.local/share/opencode/opencode.db | 161 sessions, 15,778 messages, 59,004 parts (15,159 tool, 7,063 text, 9,207 reasoning) | 732,741,632 | 2026-08-21 | 2026-09-25 | NO |
| ~/.hermes/state.db | 227 sessions (211 desktop, 7 oneshot, 7 subagent, 1 cron, 1 local), 29,221 messages (13,815 assistant, 14,315 tool, 1,091 user), 11,899 tool calls summed over sessions | 198,303,744 | 2026-10-18 | 2026-10-20 | NO |
| ~/.hermes/profiles/gideon/state.db | 3 sessions, 6 messages | 544,768 | 2026-10-19 | 2026-10-19 | NO |
| ~/.hermes/sessions | 2 request-dump json files | 743,160 | 2026-10-18 | 2026-10-19 | NO |
| ~/aien-chat-catalog/build/mac.db | 188 sessions, 11,531 messages, 75 documents | 5,730,304 | 2026-09-24 | 2026-10-19 | n/a (a catalog, not a source) |

Mac Claude project folders with jsonl (count, bytes): home 24 (47.5 MB), Developer-aienos-mv 29 (33.2 MB), aien-dev 12 (23.0 MB), drakestapleton-com 1 (19.4 MB), aienos-mv worktree imac-screensaver 2, hermes cache scratch 2, hermes delegation-live 1, two crumbproof temp folders 1 each. Per-project rows: `data/mac-inventory.txt`.

Id overlap between the two machines' originals (`data/compare-hosts.txt`, file names and session ids only): codex 982 on the Mac vs 465 on the Spark, 0 in common; claude 73 vs 3,375, 0 in common; opencode 161 vs 107, 0 in common. So the Mac sources are additional conversations, not copies.

What the archive mirrors from the MacBook: Gemini only (`pull_macbook` in `src/collectors.rs` lists only antigravity folders and `history.jsonl`). It does not mirror Mac Claude, Codex, OpenCode or Hermes.

The existing Mac catalog `~/aien-chat-catalog` (Python scripts, built 2026-10-19 12:03Z; build/mac.db, build/spark.db, build/catalog.db):
- It reads Hermes `state.db` and Claude Code transcripts plus agent files (handoffs, skills, config); nothing from Codex, OpenCode or Gemini.
- mac.db: 63 claude-code sessions (2026-09-24 to 2026-10-19), 121 hermes/desktop, 3 hermes/subagent, 1 hermes/cron; 11,531 messages by author: human 544, assistant 10,751, agent 97, system 139; 10,100 tool calls summed.
- spark.db: 3,088 claude-code sessions (2026-09-23 to 2026-10-19), 244,061 messages (human 1,633, assistant 229,191, agent 5,311, system 7,926); 185,716 tool calls summed.
- catalog.db (merged): 3,276 sessions, 255,592 messages (human 2,177), 902 dictations, 3,586 documents.
- It redacts text on the way in and has an author split (human vs agent) that the archive does not have. It is a snapshot from 2026-10-19 12:03Z and is already behind the live Claude sessions.
- Python-based, outside our stack. It is a reference for the human/agent split, not a plan.

## 1e. Gaps

Days between the first and last record with zero records (UTC dates; `data/spark-inventory.txt` end; `data/records-gaps.tsv`):

| Agent | Span days | Days with records | Days with none | The empty dates |
|---|---|---|---|---|
| claude | 28 | 28 | 0 | none |
| codex | 44 | 26 | 18 | 09-07 to 09-12, 09-14 to 09-19, 09-21, 10-06 to 10-08, 10-11, 10-15 |
| gemini | 33 | 20 | 13 | 09-22, 10-02, 10-04, 10-06 to 10-12, 10-15 to 10-17 |
| muse | 15 | 2 | 13 | 09-21 to 10-03 |
| opencode | 16 | 13 | 3 | 09-21, 09-28, 09-29 |

Codex: the Spark source files for those dates do not exist either (folder dates are local time, record dates are UTC; Spark Codex files in the 10/15 folder carry 10-16 UTC timestamps). So these are days with no Codex session on the Spark, or sessions that live only on the Mac.

Sources present on disk but not in the archive (all counts above):
1. Mac Codex: 982 files, 3.95 GB, 2026-07-27 to 2026-09-29, plus 2 archived sessions.
2. Mac Claude: 73 files, 128 MB, 2026-09-24 to 2026-10-20 (still growing).
3. Mac OpenCode: 161 sessions, 732 MB database, 2026-08-21 to 2026-09-25.
4. Mac Hermes: 227 + 3 sessions, 29,221 + 6 messages, 2026-10-18 to 2026-10-20.
5. Spark Hermes: 3 sessions, 37 messages (2026-10-20); its state.db starts on 2026-10-20 and no older Spark Hermes conversation data is on disk (UNVERIFIED whether an older store was removed).
6. Spark OpenCode tool parts (5,905), reasoning parts (1,684), patch parts (23): in the live database, not mirrored.
7. Spark Claude non-JSONL files (3,524): subagent metadata, tool-results, pdf attachments.
8. Spark Codex `history.jsonl` (330 lines) and Spark OpenCode `storage`/`tool-output` folders: present, not collected (not counted further).

Agents with no collector: Hermes (checked: `pass()` in `src/main.rs` runs claude, codex, opencode, gemini, muse only; AGENTS in `src/core.rs` lists five names; `org-check "hermes agent-archive collector"` returned CHECKED org:554f4b6497f1, 98 repos, 0 hits at 2026-10-20T12:53:59Z, with a warning that the mirror refresh had failures, so the zero is not proof).

Formats marked UNVERIFIED by agent-archive: Gemini (protobuf field numbers inferred from sampling; thinking text and `-shm` handling noted in its README); Muse is "partly verified" (event names used differ from the design note). Gemini reply "thinking" is not turned into records.
Unverified by me: how many of the 585 Gemini sessions are complete; the Gemini records cover 20 of 33 days while the Mac Gemini database files cover 2026-09-16 to 2026-10-18, which has not been reconciled (NOT_RUN: decoding blobs would read content).

Caps (answered from `src/core.rs` at 47721c7, not guessed):
- `Record::txt_line` cuts at `TXT_MAX_CHARS = 8000` characters and is used only for `latest/<agent>.txt`.
- `latest/<agent>.jsonl` and `.txt` keep the last `LATEST_LINES = 20000` records.
- `records/` are written by `emit()` via `Record::to_json`, which uses the full `text`. Confirmed by data: the longest record text per agent is 277,148 chars (claude), 130,914 (codex), 130,920 (gemini), 49,299 (opencode), so records/ keep full text and `records/` is the source for P1, not `latest/`.
- Date of a record is the message UTC date; the Codex folder date is local time.
- Not cap related, but P1 must know: Claude records keep only `text` blocks; the parser drops all `tool_use`, `tool_result`, thinking blocks and image content. Codex keeps `message` records only; `custom_tool_call` and `function_call` stay raw.

The installed binary `~/.local/bin/agent-archive` was built 2026-10-04 16:01 and the repo head is 47721c7; I did not verify that the binary was built from that exact commit (UNVERIFIED).
