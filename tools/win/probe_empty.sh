# Procura --blocklist-type (ou outra opcao) com valor vazio no dump do bindgen.
export PATH="/usr/bin:/bin:$PATH"
ARGS=/tmp/args_nak3.txt
[ -f "$ARGS" ] || { echo "sem dump"; exit 1; }
echo "== linhas --blocklist-type cujo proximo arg e outra flag =="
awk '/^--blocklist-type$/{getline n; if (n ~ /^--/) print "VAZIA antes de: " n}' "$ARGS" | head -5
echo "== total blocklist =="
grep -ac '^--blocklist-type$' "$ARGS"
echo "== ultimas 8 linhas bindgen-side =="
awk '/^--no-layout-tests$/{f=1} f' "$ARGS" | awk '/^--$/{exit} {print}' | tail -8