# Bissecta as opcoes bindgen-side para achar qual quebra o nak_bindings.
export PATH="/usr/bin:/bin:$PATH"
ARGS=/tmp/args_nak3.txt
HDR=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/mesa-switch/src/nouveau/compiler/nak_bindings.h
mapfile -t CLANG < <(awk '/^--$/{f=1; next} f' "$ARGS" | grep -av '^-MQ\|^-MF\|^-MT\|^-MD\|^-MP\|^-MG\|^-pthread')
BG=/c/Users/barba/.cargo/bin/bindgen.exe
try() {
    "$BG" "$@" "$HDR" --output /tmp/bisect.rs -- "${CLANG[@]}" > /tmp/bisect_out.txt 2>&1
    echo "exit=$?"
}
echo "== 1: so --wrap-unsafe-ops =="
try --wrap-unsafe-ops | tail -1
echo "== 2: so --blocklist-type pipe_format.* =="
try --blocklist-type 'pipe_format.*' | tail -1
echo "== 3: so --raw-line =="
try --raw-line '#![allow(clippy::all)]' | tail -1
echo "== 4: so --with-derive-default =="
try --with-derive-default | tail -1
echo "== 5: so --rust-target/edition =="
try --rust-target 1.99.0 --rust-edition 2021 | tail -1
echo "== 6: so --no-prepend-enum-name =="
try --no-prepend-enum-name | tail -1