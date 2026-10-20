cd ~/aien-chat-catalog
for db in build/mac.db build/spark.db build/catalog.db; do
 echo "== $db"; for t in $(sqlite3 -readonly $db ".tables"); do echo "  $t $(sqlite3 -readonly $db "select count(*) from \"$t\"" 2>&1)"; done; done
sqlite3 -readonly build/mac.db ".schema sessions" | cut -c1-200 | head -30
