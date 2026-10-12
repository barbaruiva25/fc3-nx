# 02 — Estado atual (2026-10-11, noite)

## O que funciona

- Extração do jogo: OK (5,77 GB)
- Codegen (XEX -> C++): OK, 883 funcoes
- Build do PC (`out/pc/fc3.exe`, 170 MB): OK
- **Boot no PC: passa do crash de memoria.** Monta VFS, tabela de funcoes, D3D12 (AMD RX 6600), SDL,
  shader storage, timer/interrupto (`SetInterruptCallback`). Roda 45+ s sem travar.
- Toolchain completa instalada do zero (ver `03-ambiente.md`)
- **`libvulkan.a` do NVK: CONSTRUIDO (91 MB).** ~20 obstaculos resolvidos, ver `05-nvk.md`.
- **NRO: CONSTRUIDO (`out/nx/fc3.nro`, 170,5 MB).** Link final passou apos `switch-libzstd` e
  `app/src/me/me_switch_stubs.cpp` (stubs do Switch para renderer desligado: `Enabled=false`,
  `CreateGraphicsSystem=nullptr`, `PresentedSwaps=0`, `SetPresentHook=no-op).
- **Pacote SD: PRONTO (`out/nx/sdcard/switch/fc3-nx/`).** Com `-IncludeGame -LooseGame` (o pack de
  5,9 GB excede o limite de 4 GB do FAT32; em pasta solta o console monta direto).

## O que trava

### A. Boot para em `update:\patch.dat` (dados, nao emulacao)

```
[NtCreateFile] FAILED: path='UPDATE:\patch.fat' -> 0xc000000f
[error] XamShowDirtyDiscErrorUI called!
```

O jogo pede o **Title Update** empacotado como par `patch.dat` + `patch.fat`. Nao esta no ISO
(nenhum dos 17 `.fat` o lista) — no console vem da particao de update. Localizado:
`Far Cry 3 (World) (v5) (6F6EAD36) (Title Update).zip`, 7,48 MB, na colecao
`microsoft_xbox360_title-updates` do archive.org. O Media ID `6F6EAD36` bate com o XEX: e o TU certo.
**Mas o download direto da 403** (`access-restricted-item: true`): precisa de conta + emprestimo manual.
Documento completo: `docs/fc3/BLOQUEIO-PATCH-DAT.md`.

### B. `libvulkan.a` ainda nao existe (build em andamento)

O build do mesa-switch chega a ~1190/1521 passos e vinha revelando um erro novo por rodada. Estado:
~20 obstaculos resolvidos, lista do bindgen/Rust sendo atacada agora. Detalhe em `05-nvk.md`.

### Realidade do escopo

Etapa 1 de 4. Mesmo com `.nro` + TU, o resultado e um jogo que inicializa — **nao um jogo jogavel**.
Etapa 2 (renderer nativo) nao comecada e e a parte cara. O usuario foi informado e escolheu
"continuar no FC3 ate o .nro". The Sims 3 (PC/DirectX9) foi descartado como alternativa: exigiria
front-end novo no SDK e jogaria fora tudo que esta pronto.