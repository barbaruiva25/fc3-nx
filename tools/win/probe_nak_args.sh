#!/bin/sh
# Mostra os argumentos finais que o wrapper do bindgen passa ao libclang e roda o clang de verdade
# em -fsyntax-only com eles, para ver o erro que o panic do bindgen esconde.
export PATH="/usr/bin:/bin:$PATH"
W=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx/tools/win/bindgen-switch-fc3.sh
export MESA_SWITCH_BINDGEN=/c/Users/barba/.cargo/bin/bindgen.exe
export DEVKITPRO=/opt/devkitpro
export MESA_SWITCH_DEBUG_ARGS=/tmp/nak_clang_args.txt
cd /c/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx/out/mesa || exit 1
CMD=$(sed -n '5526p' build.ninja | sed 's/^ *COMMAND = //')
eval "DEBUG_ARGS=1 $CMD" 2>&1 | head -5
echo "== args salvos =="
wc -l /tmp/nak_clang_args.txt 2>/dev/null || echo "(wrapper ainda nao grava; ver abaixo)"