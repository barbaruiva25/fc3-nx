# Bissecta por GRUPOS: tudo menos um grupo por vez.
export PATH="/usr/bin:/bin:$PATH"
ARGS=/tmp/args_nak3.txt
HDR=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/mesa-switch/src/nouveau/compiler/nak_bindings.h
mapfile -t CLANG < <(awk '/^--$/{f=1; next} f' "$ARGS" | grep -av '^-MQ\|^-MF\|^-MT\|^-MD\|^-MP\|^-MG\|^-pthread')
mapfile -t ALLB < <(awk '/^--no-layout-tests$/{f=1} f' "$ARGS" | awk '/^--$/{exit} {print}' | grep -av '^--no-layout-tests$\|^--opaque-type$\|^__sFILE$\|nodump')
# ALLB inclui header relativo e --output /C/...; troca output para /tmp
BG=/c/Users/barba/.cargo/bin/bindgen.exe
run() {
    local out=$1; shift
    local a=() skip=0
    for x in "${ALLB[@]}"; do
        if [ "$skip" = "1" ]; then skip=0; continue; fi
        if [ "$x" = "--output" ]; then a+=("--output" "$out"); skip=1; continue; fi
        case "$x" in ../../../*) a+=("$HDR") ;; /C/*) continue ;; *) a+=("$x") ;; esac
    done
    "$BG" "$@" "${a[@]}" -- "${CLANG[@]}" > /tmp/g_out.txt 2>&1
    echo "exit=$? $(tail -1 /tmp/g_out.txt | cut -c1-80)"
}
echo "== tudo MENOS --wrap-unsafe-ops =="
# (implementado via filtro: tira --wrap-unsafe-ops da lista)
mapfile -t NWRAP < <(printf '%s\n' "${ALLB[@]}" | grep -av '^--wrap-unsafe-ops$')
BG2() { "$BG" "$@" -- "${CLANG[@]}" > /tmp/g_out.txt 2>&1; echo "exit=$? $(tail -1 /tmp/g_out.txt | cut -c1-80)"; }
# monta sem wrap
a=() skip=0
for x in "${ALLB[@]}"; do
    if [ "$skip" = "1" ]; then skip=0; continue; fi
    if [ "$x" = "--output" ]; then a+=("--output" "/tmp/g1.rs"); skip=1; continue; fi
    case "$x" in
        --wrap-unsafe-ops) continue ;;
        ../../../*) a+=("$HDR") ;; /C/*) continue ;; *) a+=("$x") ;;
    esac
done
"$BG" "${a[@]}" -- "${CLANG[@]}" > /tmp/g_out.txt 2>&1
echo "sem-wrap exit=$? $(tail -1 /tmp/g_out.txt | cut -c1-80); ls: $(ls -la /tmp/g1.rs 2>/dev/null | awk '{print $5}')"