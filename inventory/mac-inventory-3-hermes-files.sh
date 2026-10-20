cd ~/.hermes
ls | sed -n '60,120p' | tr '\n' ' '; echo
echo "dbs:"; find . -maxdepth 3 -name '*.db' -exec stat -f '%N %z %Sm' -t %F {} + 2>/dev/null | grep -v -E 'node_modules|cache/' | head -20
echo "sessions dir: $(find sessions -type f 2>/dev/null | wc -l | tr -d ' ') files"
for d in sessions profiles; do [ -d $d ] && echo "$d: files=$(find $d -type f | wc -l | tr -d ' ') bytes=$(find $d -type f -exec stat -f '%z' {} + | awk '{s+=$1}END{print s+0}')"; done
echo "state.db:"; ls -la state.db* 2>&1 | head
