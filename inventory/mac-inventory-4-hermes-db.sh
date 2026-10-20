cd ~/.hermes
for db in state.db profiles/gideon/state.db; do
  echo "== $db"
  echo "sessions: $(sqlite3 -readonly $db "select count(*), date(min(started_at),'unixepoch'), date(max(started_at),'unixepoch') from sessions")"
  echo "messages: $(sqlite3 -readonly $db "select count(*), date(min(timestamp),'unixepoch'), date(max(timestamp),'unixepoch') from messages")"
  echo "roles:"; sqlite3 -readonly $db "select role,count(*) from messages group by role"
  echo "sources:"; sqlite3 -readonly $db "select source,count(*) from sessions group by source"
  echo "tool_calls(sum sessions.tool_call_count): $(sqlite3 -readonly $db "select sum(tool_call_count) from sessions")"
  echo "messages with tool_calls column non-null:"; sqlite3 -readonly $db "select count(*) from messages where tool_calls is not null and tool_calls!=''" 2>&1
done
echo "== sessions dir files"; find sessions -type f -exec stat -f '%N %z %Sm' -t %F {} + | sed 's#[0-9a-f]\{8,\}#<h>#g'
