# Roda o clang DE VERDADE em -fsyntax-only com os mesmos args do bindgen, para ver o
# diagnostico que o panic do bindgen esconde.
export PATH="/usr/bin:/bin:$PATH"
ARGS=/tmp/args_nak3.txt
HDR=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/mesa-switch/src/nouveau/compiler/nak_bindings.h
[ -f "$ARGS" ] || { echo "sem dump; rode probe_nak3.sh antes"; exit 1; }
CLANG=$(command -v clang || echo "/c/Program Files/LLVM/bin/clang")
CLANG_ARGS=$(awk '/^--$/{f=1; next} f' "$ARGS" | grep -av '^-MQ\|^-MF\|^-MT\|^-MD\|^-MP\|^-MG\|^-pthread' | tr '\n' ' ')
echo "== clang -fsyntax-only =="
eval "\"$CLANG\" -fsyntax-only $CLANG_ARGS \"$(cygpath -w "$HDR")\"" 2>&1 | head -25
echo "exit=$?"