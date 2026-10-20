cd ~
echo "== claude per project (jsonl count, bytes, oldest, newest)"
for d in .claude/projects/*; do
  n=$(find "$d" -type f -name '*.jsonl' | wc -l | tr -d ' ')
  b=$(find "$d" -type f -name '*.jsonl' -exec stat -f '%z' {} + 2>/dev/null | awk '{s+=$1}END{print s+0}')
  o=$(find "$d" -type f -name '*.jsonl' -exec stat -f '%m' {} + 2>/dev/null | sort -n | head -1)
  w=$(find "$d" -type f -name '*.jsonl' -exec stat -f '%m' {} + 2>/dev/null | sort -n | tail -1)
  [ -n "$o" ] && echo "$(basename $d)	$n	$b	$(date -u -r $o +%F)	$(date -u -r $w +%F)"
done
echo "== codex files per YYYY/MM"
find .codex/sessions -name '*.jsonl' | sed 's#^\.codex/sessions/##' | cut -d/ -f1-2 | sort | uniq -c
echo "codex other files: $(find .codex -maxdepth 1 -type f | wc -l | tr -d ' ') ; archived_sessions: $(find .codex/archived_sessions -type f 2>/dev/null | wc -l | tr -d ' ')"
echo "== opencode db"
db=.local/share/opencode/opencode.db
for t in session message part; do echo "$t $(sqlite3 -readonly $db "select count(*) from $t")"; done
sqlite3 -readonly $db "select date(min(time_created)/1000,'unixepoch'), date(max(time_created)/1000,'unixepoch') from session"
sqlite3 -readonly $db "select json_extract(data,'\$.type') t, count(*) from part group by t order by 2 desc" | head -8
