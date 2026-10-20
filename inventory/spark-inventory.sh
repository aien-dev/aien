#!/bin/bash
# Counts only. Re-runnable. Prints sections for LOG_INVENTORY.md 1a to 1c and 1e. Never prints message text.
A=$HOME/archive/agent-chats
echo "## 1a records per agent (files, first, last, bytes, lines)"
for a in $(ls $A/records); do cd $A/records
  echo "$a files=$(ls $a|wc -l) first=$(ls $a|head -1|sed 's/.jsonl//') last=$(ls $a|tail -1|sed 's/.jsonl//') bytes=$(cat $a/*.jsonl|wc -c) records=$(cat $a/*.jsonl|wc -l)"
  echo "  roles: $(cat $a/*.jsonl | jq -r .role | sort | uniq -c | tr '\n' ' ')"
  echo "  hosts: $(cat $a/*.jsonl | jq -r .host | sort | uniq -c | tr '\n' ' ')"
  echo "  sessions: $(cat $a/*.jsonl | jq -r .session | sort -u | wc -l) max_text_chars: $(cat $a/*.jsonl | jq '.text|length' | sort -n | tail -1)"
done
echo "## 1b raw mirror per agent/host"
cd $A/raw; for d in */*; do
  echo "$d files=$(find $d -type f|wc -l) bytes=$(find $d -type f -printf '%s\n'|awk '{s+=$1}END{print s+0}') oldest_mtime=$(find $d -type f -printf '%TY-%Tm-%Td\n'|sort|head -1) newest_mtime=$(find $d -type f -printf '%TY-%Tm-%Td\n'|sort|tail -1)"; done
for d in claude/spark codex/spark muse/spark opencode/spark; do
  echo "tool evidence in raw/$d (jsonl lines): total=$(find $d -name '*.jsonl' -print0 | xargs -0 cat | wc -l)"
  for p in '"type":"tool_use"' '"type":"tool_result"' '"type":"function_call"' '"type":"function_call_output"' '"type":"custom_tool_call"' '"type":"custom_tool_call_output"'; do
    echo "  [$p] $(find $d -name '*.jsonl' -print0 | xargs -0 grep -c -h -F -- "$p" | awk '{s+=$1}END{print s+0}')"; done
done
echo "muse payload_type containing 'tool': $(find muse/spark -name session.jsonl -print0 | xargs -0 cat | jq -r '.payload_type // ""' | grep -c -i tool)"
echo "## 1c Spark original sources"
cd ~/.claude/projects; echo "claude projects=$(ls|wc -l) jsonl=$(find . -name '*.jsonl'|wc -l) jsonl_bytes=$(find . -name '*.jsonl' -printf '%s\n'|awk '{s+=$1}END{print s}') other_files=$(find . -type f ! -name '*.jsonl'|wc -l) oldest=$(find . -name '*.jsonl' -printf '%TY-%Tm-%Td\n'|sort|head -1) newest=$(find . -name '*.jsonl' -printf '%TY-%Tm-%Td\n'|sort|tail -1)"
cd ~/.codex/sessions; echo "codex jsonl=$(find . -name '*.jsonl'|wc -l) bytes=$(find . -name '*.jsonl' -printf '%s\n'|awk '{s+=$1}END{print s}') oldest=$(find . -name '*.jsonl' -printf '%TY-%Tm-%Td\n'|sort|head -1) newest=$(find . -name '*.jsonl' -printf '%TY-%Tm-%Td\n'|sort|tail -1) archived_sessions_files=$(find ~/.codex/archived_sessions -type f|wc -l)"
db=~/.local/share/opencode/opencode.db; echo "opencode.db bytes=$(stat -c %s $db) mtime=$(stat -c %y $db|cut -c1-10)"; for t in session message part event; do echo "  $t=$(sqlite3 -readonly $db "select count(*) from $t")"; done
sqlite3 -readonly $db "select 'part types', json_extract(data,'\$.type'), count(*) from part group by 2 order by 3 desc" | tr '\n' ' '; echo
echo "  session span: $(sqlite3 -readonly $db "select date(min(time_created)/1000,'unixepoch')||' to '||date(max(time_created)/1000,'unixepoch') from session")"
for s in antigravity antigravity-cli antigravity-ide; do c=~/.gemini/$s/conversations; echo "gemini $s: db=$(find $c -name '*.db' 2>/dev/null|wc -l) wal=$(find $c -name '*.db-wal' 2>/dev/null|wc -l) wal_nonempty=$(find $c -name '*.db-wal' -size +0 2>/dev/null|wc -l) bytes=$(find $c -type f -printf '%s\n' 2>/dev/null|awk '{s+=$1}END{print s+0}')"; done
m=~/.local/share/muse; echo "muse session.jsonl=$(find $m/sessions -name session.jsonl|wc -l) bytes=$(find $m -type f -printf '%s\n'|awk '{s+=$1}END{print s}') tui_history_lines=$(wc -l < $m/tui-history.jsonl)"
h=~/.hermes; echo "hermes dir_bytes=$(du -sb $h | cut -f1) sessions_dir_files=$(find $h/sessions -type f|wc -l) state.db bytes=$(stat -c %s $h/state.db)"
echo "  sessions/messages: $(sqlite3 -readonly $h/state.db "select count(*) from sessions") / $(sqlite3 -readonly $h/state.db "select count(*) from messages") span $(sqlite3 -readonly $h/state.db "select date(min(timestamp),'unixepoch')||' to '||date(max(timestamp),'unixepoch') from messages")"
sqlite3 -readonly $h/state.db "select 'hermes roles', role, count(*) from messages group by role" | tr '\n' ' '; echo
echo "## 1e cursor check (archive state vs source)"
cd $A/state
for spec in "claude:$HOME/.claude/projects" "codex:$HOME/.codex/sessions"; do a=${spec%%:*}; root=${spec#*:}
  jq -r 'to_entries[]|"\(.key)\t\(.value.pos)"' $a.json | sort > /tmp/cur-$a.tsv; (cd $root && find . -name '*.jsonl' -printf '%P\t%s\n' | sort) > /tmp/src-$a.tsv
  echo "$a cursors=$(wc -l < /tmp/cur-$a.tsv) sources=$(wc -l < /tmp/src-$a.tsv)"
  join -t$'\t' -a1 -a2 -e MISSING -o 0,1.2,2.2 /tmp/cur-$a.tsv /tmp/src-$a.tsv | awk -F'\t' '{ if($2=="MISSING"){nc++} else if($3=="MISSING"){ns++} else { d=$3-$2; if(d>0){lag++; lb+=d} else if (d<0){neg++} } } END{print "  source_without_cursor="nc+0" cursor_without_source="ns+0" sources_with_unread_bytes="lag+0" unread_bytes_total="lb+0" cursor_past_end="neg+0}'
done
echo "gemini cursors=$(jq 'keys|length' gemini.json) opencode cursors=$(jq -c . opencode.json | cut -c1-80) muse cursors=$(jq 'keys|length' muse.json)"
echo "## 1e record gaps (agent first last span_days days_with_records days_without) and the missing dates"
cd $A/records
for a in *; do first=$(ls $a | head -1 | sed 's/.jsonl//'); last=$(ls $a | tail -1 | sed 's/.jsonl//')
  span=$(( ($(date -u -d $last +%s) - $(date -u -d $first +%s))/86400 + 1 )); have=$(ls $a | wc -l)
  missing=""; d=$first; end=$(date -u -d "$last + 1 day" +%F)
  while [ "$d" != "$end" ]; do [ -f $a/$d.jsonl ] || missing="$missing $d"; d=$(date -u -d "$d + 1 day" +%F); done
  echo "$a $first $last $span $have $((span-have)) missing:$missing"
done
