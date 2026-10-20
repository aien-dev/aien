cd ~/aien-chat-catalog
ls -la build/ | head; ls | head -20
db=build/mac.db
echo "size $(stat -f %z $db) mtime $(stat -f %Sm -t %FT%TZ $db)"
for t in $(sqlite3 -readonly $db ".tables"); do echo "$t $(sqlite3 -readonly $db "select count(*) from \"$t\"" 2>&1)"; done
