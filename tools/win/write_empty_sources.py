"""Escreve arquivos vazios (com um comentario no .h).

Usado pelas regras do mesa-switch que geram nvkcl.cpp / nvkcl.h a partir de nvkcl.spv. Ver o comentario
no src/nouveau/vulkan/meson.build: o modulo so e usado pelo copy engine, que os NROs liberados deixam
desligado, e gerar o de verdade exige mesa_clc + vtn_bindgen2 de um build nativo do Mesa.
"""
import pathlib
import sys


def main() -> None:
    banner = sys.argv[1]
    for path in sys.argv[2:]:
        p = pathlib.Path(path)
        p.write_text(banner if p.suffix == '.h' else '')


if __name__ == '__main__':
    main()