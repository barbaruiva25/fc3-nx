#!/bin/bash
# Build NATIVO do mesa_clc e do vtn_bindgen2, que o cross build precisa no PATH.
#
# Por que este passo existe
# ------------------------
# Com -Dmesa-clc=system, meson.build:972 aceita um stub no lugar de mesa_clc porque with_clc=false
# (meson.build:957-960 e 971-975: nenhum driver CLC, gallium-rusticl desligado). O stub passa no
# find_program... ate o build chegar em src/nouveau/vulkan/nvkcl.spv, que e compilado de verdade:
#
#   while executing ['.../out/tools/clc/mesa_clc', '-o', 'src/nouveau/vulkan/nvkcl.spv', ...]
#   mesa_clc: stub do fc3-nx
#
# Entao o nativo nao e opcional: e o binario real. build-switch.sh faz exatamente isto
# ("meson setup builddir-native ... && ninja -C builddir-native src/compiler/clc/mesa_clc
# src/compiler/spirv/vtn_bindgen2") e e o que este script faz.
#
#   bash build_clc_native.sh [jobs]
#
# Os dois binarios sao instalados em <repo>/out/tools/clc, que nvk_meson_setup.sh e nvk_meson_build.sh
# ja colocam no PATH.
set -e
export PATH="/usr/bin:/bin:$PATH"

FC3=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx
MESA=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/mesa-switch
BUILDDIR="$MESA/builddir-native"
CLCDIR="$FC3/out/tools/clc"
JOBS=${1:-16}

# Compilador NATIVO: o gcc MINGW64 do MSYS2, nao o clang do Windows.
#
# clang do LLVM em Windows nao serve aqui: meson diz "Compiler clang cannot compile programs" porque ele
# nao acha a toolchain de linkagem/linkerDriver de um jeito que o meson aceite neste ambiente. O
# mingw64/bin do proprio MSYS2 e o compilador nativo que o build-switch-msys2.sh do mesa usa.
# Precisa de: mingw-w64-x86_64-gcc (tools/win/install_rust_host_gcc.sh).
export PATH="/mingw64/bin:$PATH"
export CC=gcc
export CXX=g++
export LD=ld
export DLLTOOL=dlltool
export WINDRES=windres
echo "gcc:   $(command -v gcc || echo AUSENTE)"
echo "g++:   $(command -v g++ || echo AUSENTE)"
echo "dlltool: $(command -v dlltool || echo AUSENTE)"

# clang do host: o nvkmd/switch precisa de um clang que leia os headers do devkitPro, e o
# bindgen-switch-wrapper.sh procura `command -v clang` quando nao acha /clangarm64/bin/clang.exe.
# Sem isto CLANG_BIN fica vazio e o wrapper morre em "$("$CLANG_BIN" -print-resource-dir)".
export PATH="/c/Program Files/LLVM/bin:$PATH"
echo "clang: $(command -v clang || echo AUSENTE)"

mkdir -p "$CLCDIR"
rm -rf "$BUILDDIR"

echo "=== meson setup (nativo) ==="
cd "$MESA"
/usr/bin/python -m mesonbuild.mesonmain setup "$BUILDDIR" . \
    -Dvulkan-drivers= \
    -Dgallium-drivers= \
    -Dplatforms= \
    -Dglx=disabled \
    -Degl=disabled \
    -Dopengl=false \
    -Dgles1=disabled \
    -Dgles2=disabled \
    -Dtools=[] \
    -Dbuild-tests=false \
    -Dllvm=enabled \
    -Dshared-llvm=enabled \
    -Dmesa-clc=enabled \
    -Dprecomp-compiler=enabled \
    -Dinstall-mesa-clc=true \
    --buildtype=release

echo "=== ninja: mesa_clc + vtn_bindgen2 ==="
ninja -C "$BUILDDIR" -j "$JOBS" src/compiler/clc/mesa_clc src/compiler/spirv/vtn_bindgen2

echo "=== instalando em $CLCDIR ==="
find "$BUILDDIR" -name 'mesa_clc*' -type f -perm -u+x -exec cp {} "$CLCDIR/mesa_clc" \; || true
find "$BUILDDIR" -name 'vtn_bindgen2*' -type f -perm -u+x -exec cp {} "$CLCDIR/vtn_bindgen2" \; || true

ls -la "$CLCDIR"
echo "=== teste ==="
"$CLCDIR/mesa_clc" --version 2>&1 | head -2 || echo "mesa_clc nao respondeu (veja acima)"