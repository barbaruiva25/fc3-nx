# 02 — Estado atual (2026-10-13, manha; sessao com codegen+boot em loop)

## O que funciona

- Extração do jogo: OK (5,77 GB)
- Codegen (XEX -> C++): OK, 883 funcoes (~13 min por rodada: 769 s / 757 s medidos em 13/10)
- Build do PC (`out/pc/fc3.exe`, 162 MB): OK
- **Boot no PC: passa do crash de memoria.** Monta VFS, tabela de funcoes, D3D12 (AMD RX 6600), SDL,
  shader storage, timer/interrupto (`SetInterruptCallback`).
- TU EXTRAIDO e montavel: `assets/update/` tem `patch.dat` (3,4 MB) + `patch.fat`; `REX_update_data_root`
  monta em `\Device\Harddisk0\PartitionUpdate`. **O `boot_test.ps1` agora monta sozinho** (param
  `-UpdateRoot`, padrao `__auto__` -> `..\assets\update` quando existe).
- Toolchain completa instalada do zero (ver `03-ambiente.md`)
- **`libvulkan.a` do NVK: CONSTRUIDO (95 MB).** ~20 obstaculos resolvidos, ver `05-nvk.md`.
- **NRO: CONSTRUIDO (`out/nx/fc3.nro`, 170,5 MB).** Link final passou apos `switch-libzstd` e
  `app/src/me/me_switch_stubs.cpp` (stubs do Switch para renderer desligado: `Enabled=false`,
  `CreateGraphicsSystem=nullptr`, `PresentedSwaps=0`, `SetPresentHook=no-op).
- **Pacote SD: PRONTO (`out/nx/sdcard/switch/fc3-nx/`).** Com `-IncludeGame -LooseGame` (o pack de
  5,9 GB excede o limite de 4 GB do FAT32; em pasta solta o console monta direto).
- Loop 13/10 manha: 2 FATALs resolvidos via `runtime_gap_resolver` (`0x82DA59D8` gap 48B,
  `0x829BDE90` gap 16B, ambos com `push`); symbolizer funciona na forma VA
  (`llvm-symbolizer --exe=fc3.exe 0x140000000+RVA`, a forma RVA pura retorna `??:0`).

## O que trava

### A. RESOLVIDO (dados): `update:\patch.dat` extraido; boot_test monta sozinho

Ver `docs/fc3/BLOQUEIO-PATCH-DAT.md` + `tools/win/boot_test.ps1` (param `-UpdateRoot`).

### B. Boot atual: ponteiros para memoria nao mapeada no init de conteudo (13/10)

- SEM TU (artefato, boots 042-044 sem `REX_update_data_root`): `FATAL 0x829BDE90` (registrado) e
  crash guest `0x0502FF08` em `sub_82386818` (busca em arvore, `fc3_recomp.173.cpp:308`) — raiz
  valida (`0x40001DB4`, arvore global em `0x83E97FC8`), no corrompido no meio do caminho; chaves 6..13.
- COM TU (boot 045, 7 s): crash guest `0x04020000` em `sub_82385378` (`fc3_recomp.288.cpp:326`,
  `lwz r4,0(r7)`, `[r3+4]` invalido) — vetor com ponteiro de dados nao mapeado.
- Hipotese principal: threads que o jogo cria NUNCA executam (workaround do crash `0x13C` salva os
  registradores mas o `KeSetCurrentStackPointers` do SDK retorna em vez de despachar) — estruturas
  de conteudo ficam meio-construidas. A correcao real e marcar a export como noreturn no codegen
  (conceito nao existe no SDK: sem `kNoReturn`; exige cirurgia no SDK + rodada de codegen). Ver `04`.
- Hook temporario ativo: `tree89218` em `app/src/fc3_debug_hooks.cpp` (remover quando fechar).

### Realidade do escopo

Etapa 1 de 4. Mesmo com `.nro` + TU, o resultado e um jogo que inicializa — **nao um jogo jogavel**.
Etapa 2 (renderer nativo) nao comecada e e a parte cara. O usuario foi informado e escolheu
"continuar no FC3 ate o .nro". The Sims 3 (PC/DirectX9) foi descartado como alternativa: exigiria
front-end novo no SDK e jogaria fora tudo que esta pronto.