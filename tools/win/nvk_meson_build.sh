#!/bin/bash
# Compila e instala o mesa-switch -> libvulkan.a estatico para o NRO do Switch.
# Chamado por tools/win/build_nvk.ps1. Ver nvk_meson_setup.sh para qual commit tem o driver NVK.
#
#   bash nvk_meson_build.sh <source> <builddir> <jobs> <host-python>
#
# PATH: o ninja tambem roda fora do script de setup, entao tudo que o build precisa vai aqui.
#   out/glslang/StandAlone  glslangValidator, para compilar qualquer .spv
#   out/tools/clc           mesa_clc / vtn_bindgen2 (stubs, ou os reais se o build nativo existir)
#   LLVM/bin               clang, que o bindgen-switch-wrapper.sh procura com `command -v clang`.
#                           Sem isto CLANG_BIN fica vazio e o wrapper morre na linha 37 em
#                           "$("$CLANG_BIN" -print-resource-dir)".
set -e
export PATH="/usr/bin:/bin:$PATH"

FC3=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx
export PATH="$FC3/out/glslang/StandAlone:$FC3/out/tools/clc:/c/Program Files/LLVM/bin:$PATH"

SRC="$1"
BUILD="$2"
JOBS="$3"
HOST_PY="$4"

echo "== ferramentas"
for t in clang glslangValidator.exe ninja; do
    printf '  %-20s %s\n' "$t" "$(command -v "$t" || echo AUSENTE)"
done

# HOST_PY vazio nao deve colocar "." no PATH (dirname de string vazia). O Python do MSYS2 tem meson,
# mako, setuptools, markupsafe e pyyaml (tools/win/install_mesa_deps.sh), entao nao ha o que substituir,
# e o interpretador do Windows precisa ficar fora do PATH: e o alias da Microsoft Store.
if [ -n "$HOST_PY" ] && [ -d "$(dirname "$HOST_PY")" ]; then
    export PATH="$(dirname "$HOST_PY"):$PATH"
else
    echo "== HOST_PY not given: using MSYS2's python"
fi

cd "$SRC"
ninja -C "$BUILD" -j "$JOBS" -k 0
/usr/bin/python -m mesonbuild.mesonmain install -C "$BUILD" --only-changed

echo "build+install done"
echo "== libraries"
find "$BUILD" \( -name 'libvulkan.a' -o -name 'libnvk.a' -o -name 'libnak*.a' \) -exec ls -la {} \;