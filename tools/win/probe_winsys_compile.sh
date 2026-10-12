# Reproduz, fora do ninja, o comando exato que falha em nouveau_switch_libdrm.c, para ver o que o
# gcc recebe de verdade. Sem isso o erro e "No such file or directory" em um header que existe.
#
#   bash probe_winsys_compile.sh
set -o pipefail
export PATH="/usr/bin:/bin:$PATH"
BUILD=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx/out/mesa
GCC=/opt/devkitpro/devkitA64/bin/aarch64-none-elf-gcc
SRC=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/mesa-switch

echo "== o header existe?"
ls -l "$SRC/src/gallium/winsys/nouveau/switch/nouveau.h" 2>&1

echo
echo "== o gcc com o -I do cross file, do diretorio do build"
cd "$BUILD" || exit 1
"$GCC" -c "$SRC/src/gallium/winsys/nouveau/switch/nouveau_switch_libdrm.c" \
       -o /tmp/probe.o \
       -I"$SRC/src/gallium" \
       -I"$SRC/src" 2>&1 | head -6
echo "  (vazio acima = funcionou)"

echo
echo "== o que o gcc acha que e o diretorio"
"$GCC" -E -v -x c /dev/null -I"$SRC/src/gallium" 2>&1 | sed -n '/#include <...>/,/End of search/p'

echo
echo "== versao do arquivo include"
grep -n 'winsys/nouveau' "$SRC/src/gallium/winsys/nouveau/switch/nouveau_switch_libdrm.h" | head -3