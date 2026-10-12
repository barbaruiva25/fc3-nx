#!/bin/bash
# Roda o build nativo do mesa_clc com o LLVM instalado apontado para o meson.
#
# Sem isto o setup morre em "Subproject llvm is buildable: NO / Neither a subproject directory nor a
# llvm.wrap file was found": o Mesa 26.2 pede LLVM como dependencia, nao ha wrap, e o meson nao acha o
# LLVM so por estar instalado. LLVM_DIR e o que o find_package(LLVM) do meson le.
export PATH="/usr/bin:/bin:/mingw64/bin:/c/Program Files/LLVM/bin:$PATH"
export CC=gcc CXX=g++ LD=ld DLLTOOL=dlltool WINDRES=windres
export LLVM_DIR="/c/Program Files/LLVM/lib/cmake/llvm"
export CMAKE_PREFIX_PATH="/c/Program Files/LLVM/lib/cmake/llvm"

FC3=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx
exec bash "$FC3/tools/win/build_clc_native.sh" "${1:-16}"