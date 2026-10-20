#!/bin/bash
# Session id overlap between MacBook and Spark originals (ids only, no content).
mac() { ssh -o BatchMode=yes macbook "$1"; }
mac 'cd ~/.codex/sessions && find . -name "*.jsonl" | sed "s#.*/##"' | sort > /tmp/mac-codex-names.txt
(cd ~/.codex/sessions && find . -name '*.jsonl' | sed 's#.*/##') | sort > /tmp/spark-codex-names.txt
echo "codex mac=$(wc -l < /tmp/mac-codex-names.txt) spark=$(wc -l < /tmp/spark-codex-names.txt) common=$(comm -12 /tmp/mac-codex-names.txt /tmp/spark-codex-names.txt | wc -l)"
mac 'cd ~/.claude/projects && find . -name "*.jsonl" | sed "s#.*/##"' | sort > /tmp/mac-claude-names.txt
(cd ~/.claude/projects && find . -name '*.jsonl' | sed 's#.*/##') | sort > /tmp/spark-claude-names.txt
echo "claude mac=$(wc -l < /tmp/mac-claude-names.txt) spark=$(wc -l < /tmp/spark-claude-names.txt) common=$(comm -12 /tmp/mac-claude-names.txt /tmp/spark-claude-names.txt | wc -l)"
mac 'sqlite3 -readonly ~/.local/share/opencode/opencode.db "select id from session"' | sort > /tmp/mac-oc.txt
sqlite3 -readonly ~/.local/share/opencode/opencode.db "select id from session" | sort > /tmp/spark-oc.txt
echo "opencode mac=$(wc -l < /tmp/mac-oc.txt) spark=$(wc -l < /tmp/spark-oc.txt) common=$(comm -12 /tmp/mac-oc.txt /tmp/spark-oc.txt | wc -l)"
