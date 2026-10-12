# Roda o bindgen com as opcoes bindgen-side REAIS do ninja (antes do --) + verbose.
export PATH="/usr/bin:/bin:$PATH"
ARGS=/tmp/args_nak3.txt
[ -f "$ARGS" ] || { echo "sem dump; rode probe_nak3.sh antes"; exit 1; }
HDR=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/mesa-switch/src/nouveau/compiler/nak_bindings.h
mapfile -t BIND < <(awk '/^--no-layout-tests$/{f=1} f' "$ARGS" | awk '/^--$/{exit} {print}')
mapfile -t CLANG < <(awk '/^--$/{f=1; next} f' "$ARGS" | grep -av '^-MQ\|^-MF\|^-MT\|^-MD\|^-MP\|^-MG\|^-pthread')
echo "== ${#BIND[@]} bindgen args, ${#CLANG[@]} clang args =="
echo "--- bindgen args (primeiras) ---"
printf '%s\n' "${BIND[@]}" | head -12
# Os args dumpados ja trazem header + --output; troca so o output para /tmp.
ARGS2=()
skip=0
for a in "${BIND[@]}"; do
    if [ "$skip" = "1" ]; then skip=0; continue; fi
    if [ "$a" = "--output" ]; then ARGS2+=("--output" "/tmp/nak_v2.rs"); skip=1; continue; fi
    case "$a" in
        ../../../*) ARGS2+=("$HDR") ;;
        /C/*nak_bindings.rs) continue ;;
        *) ARGS2+=("$a") ;;
    esac
done
/c/Users/barba/.cargo/bin/bindgen.exe --verbose "${ARGS2[@]}" -- "${CLANG[@]}" 2>&1 | tail -15
echo "exit=$?"
ls -la /tmp/nak_v2.rs 2>&1 | head -1