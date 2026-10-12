# 05 — Build do NVK (`libvulkan.a`): obstaculos resolvidos

Meta: `mesa-switch-install/opt/devkitpro/portlibs/switch/lib/libvulkan.a`, via
`tools/win/build_nvk.ps1 -Jobs 24`. Setup em `tools/win/nvk_meson_setup.sh`, build em
`tools/win/nvk_meson_build.sh` (ninja direto com `-k 0`; `meson compile` nao repassa flags).
Diagnostico do ninja: `tools/win/ninja_errors.sh`. Setup cruza em `mesa-switch/switch_cross_file.txt`.

Regra de ouro deste build: **binarios sao Windows nativos, caminhos do meson sao MSYS2.**
Tudo que cruza a fronteira precisa de conversao (`cygpath -w`). Tres wrappers proprios existem por isso:
`tools/win/rustc-switch-fc3.sh`, `tools/win/bindgen-switch-fc3.sh`.

## Resolvidos

1. `byacc` nao existe no MSYS2 — `meson.build:2240` acha `bison` primeiro; instalar bison resolve.
2. Python ausente no MSYS2; pip bloqueado (PEP 668) — pacotes via `pacman` (`python-mako` etc.).
3. zlib linkava como `.so` (`undefined reference to main`) — `--default-library=static`.
4. Cross file apontava para a pasta antiga do projeto — `-I` para diretorio inexistente nao da erro,
   o include so falha depois ("header faltando"). Confirmar em `out/mesa/build.ninja`.
5. Headers duplicados: `nouveau_winsys.h` declarava a API `nouveau_switch_pushbuf_*` que
   `nouveau_switch_public.h` ja declara -> removida a segunda copia.
6. `nouveau_winsys.h` incluia `winsys/nouveau/drm/nouveau.h` antes do header do Switch; mesmo include
   guard nas duas => structs do Switch viravam layout do DRM ("incompatible pointer type" em massa).
   Include do DRM agora e `#ifndef __SWITCH__`.
7. Vulkan nunca habilitado — faltava `-Dvulkan-drivers=nouveau` (valor `nouveau`, nao `nvk`).
8. EGL forcava o Gallium (`src/egl/meson.build:155` da `error()` sem ele) — GL/EGL desligados
   (`-Degl=disabled -Dopengl=false -Dgles1/2=disabled -Dglx=disabled`).
9. `-Reuse` nao rele o cross file — apos edita-lo, build do zero.
10. `rust` ausente no cross file; rustup padrao era MSVC (args `/NOLOGO` para gcc) — toolchain
    `stable-x86_64-pc-windows-gnu` + target `aarch64-unknown-linux-gnu` + wrapper proprio.
11. Probe de sanidade do Rust falhava com MINGW64 (`ld returned 53`) — wrapper deixa o probe no linker
    padrao do rustc, so poem `--target` no build real.
12. `bindgen` ausente — `bindgen-cli` 0.73.2 (`cargo install`; cbindgen nao serve; precisa de `dlltool`
    do mingw64 no PATH). Apontado via `MESA_SWITCH_BINDGEN`.
13. `mesa-clc=system` exigia os binarios — flags adicionadas; com CLC e precomp `system`, `with_clc`
    fica falso, e `find_program` e satisfeito por stubs (`out/tools/clc/`, de `tools/win/clc_stub.sh`).
    Eles falham alto se forem chamados de verdade.
14. `glslangValidator` ausente — reaproveitado o do PC (`out/glslang/StandAlone`; SPIR-V e portavel).
15. `nvkcl.spv` exige `mesa_clc` — regra trocada por copia de placeholder SPIR-V valido-mas-vazio
    (`src/nouveau/vulkan/nvkcl_placeholder.spv`), com a regra original documentada no comentario.
16. `nvkcl.cpp/h` (via `vtn_bindgen2`) — trocados por stubs reais (`nvkcl_stub.c/h`): header vazio nao
    linka porque `build_copy_indierct_shader()` chama `nvk_copy_indirect` incondicionalmente. O stub
    tem o prototipo certo e da `abort()` se o copy engine for ligado. Custom_target mantido gerando
    `nvkcl.cpp/nvkcl.h` por copia (`tools/win/copy_pair.py`).
    (So serve ao copy engine, desligado por padrao nos NROs.)

## Em ataque agora

17. bindgen/Rust (`nak_bindings.rs`, `nil_bindings.rs`, `nvh_hwref_*`, `bindings.rs`): wrapper reescrito
    com conversao `cygpath -w` de todos os `-I` MSYS2 + `--target=aarch64-none-elf` (sem ele o libclang
    cai nos headers do MSVC do host). Probe isolado (`tools/win/probe_bindgen.sh`) avanca ate os `-I`
    do build real. Ultimo grupo de erros conhecido.

## Patches na arvore do mesa (revisar antes de atualizar o checkout)

- `src/gallium/drivers/nouveau/nouveau_winsys.h` (itens 5, 6)
- `src/nouveau/vulkan/meson.build` (itens 15, 16)
- `meson.build` raiz (item: `msys`/`mingw`/`cygwin` tratados como Windows na checagem de `dl`)
- `switch_cross_file.txt` (caminhos, `rust`, `bindgen`)
- Arquivos novos: `src/nouveau/vulkan/nvkcl_placeholder.spv`, `nvkcl_stub.{c,h}`

Detalhe completo com numeros de linha: `docs/fc3/NOTAS-DE-BUILD.md` §10–§13.