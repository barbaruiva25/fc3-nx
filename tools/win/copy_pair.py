"""Copia dois arquivos de entrada para duas saidas: stub_c -> saida_0, stub_h -> saida_1.

Usado pela regra nvkcl em src/nouveau/vulkan/meson.build: em vez de gerar nvkcl.cpp/nvkcl.h com
vtn_bindgen2 (que exige o build nativo do Mesa), copiamos os stubs nvkcl_stub.c/h.
"""
import shutil
import sys


def main() -> None:
    stub_c, stub_h, out_0, out_1 = sys.argv[1:5]
    shutil.copyfile(stub_c, out_0)
    shutil.copyfile(stub_h, out_1)


if __name__ == '__main__':
    main()