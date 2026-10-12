# 07 — Inventario (caminhos exatos)

## Codigo do porte (`fc3-nx/`)

- `app/fc3_manifest.toml` — manifest do codegen (jogo, modulos)
- `app/overrides.toml` — funcoes extras (vazio por enquanto)
- `app/generated/default/` — 440 `.cpp` gerados (nao editar a mao)
- `app/src/fc3_debug_hooks.cpp` — hooks de boot + workaround do crash `0x13C`
- `app/src/me/` — renderer nativo (Etapa 2; ainda do SA2)
- `app/CMakeLists.txt`, `app/CMakePresets.json` — build PC + Switch
- `sdk/` — fork do ReXGlue (patch em `src/kernel/xboxkrnl/xboxkrnl_threading.cpp`)
- `tools/win/` — `run.ps1 env.ps1 build_switch.ps1 package_switch.ps1 build_nvk.ps1 nvk_meson_setup.sh
  nvk_meson_build.sh build_clc_native.sh rustc-switch-fc3.sh bindgen-switch-fc3.sh clc_stub.sh
  install_mesa_deps.sh install_rust_host_gcc.sh ninja_errors.sh build_direct.ps1 ninja_why.ps1
  probe_*.sh check_env.ps1` (+ `tools/scan_savegpr.ps1`, `tools/build_asset_pack.py`)
- `tools/switch/cmake/switch-devkitA64.cmake` — toolchain file do Switch
- `docs/fc3/` — `RESUMO.md PLANO.md NOTAS-DE-BUILD.md DIAGNOSTICO-BOOT-0x13C.md BLOQUEIO-PATCH-DAT.md`
- `out/` — `pc/` (build PC), `pc/logs/` (boots), `host/`, `glslang/`, `mesa/` (build NVK), `tools/clc/`

## Mesa (`mesa-switch/`, commit `1a8c1a66d6f`)

- `switch_cross_file.txt` — cross file (editado: caminhos, static, rust, bindgen)
- `src/gallium/drivers/nouveau/nouveau_winsys.h` — editado (headers)
- `src/nouveau/vulkan/meson.build` — editado (nvkcl placeholder + stubs)
- `src/nouveau/vulkan/nvkcl_placeholder.spv`, `nvkcl_stub.c`, `nvkcl_stub.h` — novos
- `meson.build` (raiz) — editado (checagem de `dl`)
- `rustc-switch-wrapper.sh`, `bindgen-switch-wrapper.sh` — originais (usamos os nossos)

## Dados

- `assets/game_root/` — ISO extraido (5,77 GB)
- `assets/update/` — pasta do `UPDATE:\` (vazia; recebe o TU convertido)
- `mesa-switch-install/` — destino do NVK (criado pelo `build_nvk.ps1`)