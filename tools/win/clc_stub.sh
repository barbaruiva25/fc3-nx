#!/bin/sh
# Stub de mesa_clc / vtn_bindgen2 para o cross build do mesa-switch nesta maquina.
#
# Por que um stub, e nao o binario de verdade
# -------------------------------------------
# Com -Dmesa-clc=system -Dprecomp-compiler=system, meson.build:957-960 deixa with_drivers_clc falso e
# meson.build:971-975 deixa with_clc igual a with_gallium_rusticl (desligado aqui). Com with_clc falso o
# CLC nao e usado em lugar nenhum. Ainda assim meson.build:972 roda
#
#     prog_mesa_clc = find_program('mesa_clc', native : true)
#
# e find_program so exige que o arquivo exista e seja executavel. build-switch.sh resolve isso
# compilando os dois de verdade num build NATIVO do Mesa, o que aqui exigiria um LLVM do host casando
# com o Mesa 26.2 - que nao esta instalado (so ha o clang 23.1.3).
#
# Este stub existe APENAS para satisfazer o find_program. Se algo realmente chamar o compilador, ele
# falha com uma mensagem que diz o que fazer, em vez de devolver lixo em silencio.
echo "mesa_clc: stub do fc3-nx. O build nativo do Mesa (veja mesa-switch/build-switch.sh, que roda" >&2
echo "  'meson setup builddir-native ... -Dllvm=enabled -Dmesa-clc=enabled -Dprecomp-compiler=enabled'" >&2
echo "  e depois 'ninja -C builddir-native src/compiler/clc/mesa_clc src/compiler/spirv/vtn_bindgen2')" >&2
echo "  nao foi feito nesta maquina, entao este compilador nao existe de verdade." >&2
exit 1