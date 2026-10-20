# inventory/

Allen P0 stream `inventory` (ledger L175). Ground truth for what conversation logs exist, where, and what is missing, before Allen P1 builds training episodes.

- `LOG_INVENTORY.md`: the tables and the plain-English summary. Start here.
- `inventory.json`: the same counts, machine readable.
- `SOURCE_MANIFEST.md`: where the access-controlled manifest lives (outside git), its digest, who may read it, deletion owner.
- `COMMANDS.md`: how to re-run everything; the `*.sh` scripts and `data/` outputs it names.

Privacy: counts, sizes, dates, hosts, paths, session ids and digests only. No message text, no manifest rows, ever, in this directory.
Everything here was counted on the Spark and, read only over ssh, on the MacBook. Nothing was run on real hardware other than those counts; qualification is NOT_RUN.
