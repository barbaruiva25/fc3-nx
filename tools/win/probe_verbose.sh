# Roda o bindgen com --verbose nos args dumpados, para ver onde o libclang morre.
export PATH="/usr/bin:/bin:$PATH"
ARGS=/tmp/args_nak3.txt
[ -f "$ARGS" ] || { echo "sem dump; rode probe_nak3.sh antes"; exit 1; }
HDR=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/mesa-switch/src/nouveau/compiler/nak_bindings.h
# lado do clang, uma opcao por linha -> array; tira -MQ/-MF/-MT/-MD/-MP/-MG/-pthread (driver-only)
mapfile -t CLANG < <(awk '/^--$/{f=1; next} f' "$ARGS" | grep -av '^-MQ\|^-MF\|^-MT\|^-MD\|^-MP\|^-MG\|^-pthread')
echo "== ${#CLANG[@]} clang args; bindgen --verbose =="
/c/Users/barba/.cargo/bin/bindgen.exe --verbose "$HDR" --output /tmp/nak_v.rs -- "${CLANG[@]}" 2>&1 | tail -30
echo "exit=$?"
ls -la /tmp/nak_v.rs 2>&1 | head -1