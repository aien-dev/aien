cd ~/aien-chat-catalog/build
for db in mac.db spark.db catalog.db; do
 echo "== $db"
 sqlite3 -readonly $db "select 'sessions_by_machine_source', machine, source, count(*), min(substr(started_at,1,10)), max(substr(started_at,1,10)) from sessions group by machine, source"
 sqlite3 -readonly $db "select 'sum_tool_calls', sum(n_tool_calls), 'subagent_sessions', sum(is_subagent) from sessions"
 sqlite3 -readonly $db ".schema messages" | head -8 | cut -c1-200
 sqlite3 -readonly $db "select 'authors', author, count(*) from messages group by author" 2>&1 | head
done
