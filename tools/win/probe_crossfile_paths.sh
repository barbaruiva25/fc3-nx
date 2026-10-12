# Diagnostico: o gcc do devkitA64 (binario Windows nativo) entende os caminhos /c/... do MSYS2?
#
# O cross file do mesa-switch declara os -I como caminhos MSYS2 absolutos. Se a conversao automatica do
# MSYS2 nao ocorrer quando o ninja lanca o compilador, esses -I viram lixo e o include falha.
#
#   bash probe_crossfile_paths.sh
export PATH="/usr/bin:/bin:$PATH"
GCC=/opt/devkitpro/devkitA64/bin/aarch64-none-elf-gcc
SRC=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/mesa-switch

echo "== gcc existe?"
ls -l "$GCC" 2>&1 | head -1

echo
echo "== o gcc ve o caminho MSYS2 /c/... ?"
cat > /tmp/probe.c <<'EOF'
#include <winsys/nouveau/switch/nouveau.h>
int main(void) { return 0; }
EOF
"$GCC" -c /tmp/probe.c -o /tmp/probe.o \
    "-I${SRC}/src/gallium" \
    "-I${SRC}/src" 2>&1 | head -4
echo "  (saida acima: 'No such file' = caminho MSYS2 NAO resolve)"

echo
echo "== e com caminho relativo a partir do build dir?="
cd /c/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx/out/mesa || exit 1
"$GCC" -c /tmp/probe.c -o /tmp/probe.o \
    -I../../../mesa-switch/src/gallium \
    -I../../../mesa-switch/src 2>&1 | head -4
echo "  (sem 'No such file' acima = caminho RELATIVO funciona)"

echo
echo "== MSYS2_ARG_CONV_EXCL = '${MSYS2_ARG_CONV_EXCL:-<vazio>}'"