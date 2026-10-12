# Bissecta os --blocklist-type: metade por vez, depois combina com o resto fixo.
export PATH="/usr/bin:/bin:$PATH"
ARGS=/tmp/args_nak3.txt
HDR=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/mesa-switch/src/nouveau/compiler/nak_bindings.h
mapfile -t CLANG < <(awk '/^--$/{f=1; next} f' "$ARGS" | grep -av '^-MQ\|^-MF\|^-MT\|^-MD\|^-MP\|^-MG\|^-pthread')
mapfile -t FIXED < <(awk '/^--no-layout-tests$/{f=1} f' "$ARGS" | awk '/^--$/{exit} {print}' | awk '/^--blocklist-type$/{getline; next} !/^--no-layout-tests$/ && !/^--opaque-type$/ && !/^__sFILE$/ && !/^\.\.\/\.\.\// && !/^\/C\//')
# FIXED: todo o resto (raw-lines, wrap, output...). blocklists entram por parametro.
mapfile -t TYPES < <(awk '/^--blocklist-type$/{getline n; print n}' "$ARGS")
echo "total blocklist-types: ${#TYPES[@]}"
BG=/c/Users/barba/.cargo/bin/bindgen.exe
runset() {
    local tag=$1; shift
    local a=(--no-layout-tests --opaque-type __sFILE)
    for t in "$@"; do a+=(--blocklist-type "$t"); done
    a+=("${FIXED[@]}")
    # FIXED tem --output mas sem valor (o valor /C/... foi filtrado); repoe /tmp
    local b=() skip=0
    for x in "${a[@]}"; do
        if [ "$skip" = "1" ]; then skip=0; continue; fi
        if [ "$x" = "--output" ]; then b+=("--output" "/tmp/bi_$tag.rs"); skip=1; continue; fi
        b+=("$x")
    done
    "$BG" "${b[@]}" "$HDR" -- "${CLANG[@]}" > /tmp/bi_out.txt 2>&1
    echo "$tag: exit=$? size=$(stat -c%s /tmp/bi_$tag.rs 2>/dev/null || echo -)"
}
HALF=$((${#TYPES[@]}/2))
runset "primeira-metade" "${TYPES[@]:0:$HALF}"
runset "segunda-metade" "${TYPES[@]:$HALF}"