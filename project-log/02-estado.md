# 02 — Estado atual (2026-10-14, 22:35; BREAKTHROUGH: boot passa do init de conteudo)

## O que funciona (atualizado)

- **BOOT PASSA DO CRASH DO VETOR.** Patch cirurgico temporario no hook `vec85378`
  (`[F90CAA20+4] := 0` na entrada da chamada #18): `PATCHED [F90CAA20+4]: 00000204 -> 0`
  e o jogo ANDA — 45 s rodando com 51 s de CPU (multithread ocupado), 808 MB, commits
  de 1,5 MB (`F2xxx size=180000`), AUDIO TOCANDO (1875 frames/10 s SDL, dado real).
  Antes: crash deterministico ha 15+ ciclos no mesmo ponto.
- O que isso prova: UM elo ruim bloqueava o boot; arvore, manager, mantenedor e vec
  estao corretos. O `w1=0x04020000` = byte+4 `0x04` (tag/comprimento pre-existente,
  nunca escrito em janela) + byte+5 `0x02` (recolor legitimo do mantenedor).
  Origem do byte+4 ainda aberta (CANDIDATO: `stw r31,4(r11)` do criador com
  comprimento 4 = string "load" — no string com tag/comprimento linkado numa cadeia
  de ponteiros). O NRO precisa do mesmo tratamento ate o fix real.
- Proximos: boot longo (180 s, rodando) para ver ate onde vai (menu? video? proximo
  crash?); depois trocar o patch por fix real ou mante-lo documentado como workaround.

## O que funciona (atualizado)

- NRO RELINKADO com o codigo atual (`out/nx/fc3.nro`, 14/10 01:00, 170,7 MB).
  Unico problema de link foi `Fc3ArmNodeWatch` (Windows-only) — stub no-op no Switch.
- Switch testado pelo usuario via DBI: SD verificado OK; crash e o mesmo do PC.
- Pista nova e forte para a proxima sessao (lida em `sdk/src/system/xfile.cpp:106-112`,
  descoberta de sessao anterior): o jogo faz leituras de arquivo para scratch fisico
  (ex. `sound_english.fat` -> `0xF90C9D40`) e o SDK materializa paginas host on demand
  para isso — SEM zerar e fora do caminho de commit guest. A pagina do no (F90CAxxx)
  divide a regiao com esse scratch. Hipotese: file-read (memcpy host-direct, sem AV,
  invisivel ao watch) escreve bytes de arquivo ("load"+A3) por cima de blocos do pool —
  ou o pool entrega blocos sobrepostos ao scratch. Teste: logar reads com destino em
  F90Cxxxx perto do crash; checar se o commit de F90CA000 veio por transferencia
  (sem zero) ou por commit guest (com zero pelo fix de hoje).

## O que funciona (atualizado)

- Codegen: 883 -> ~1174 funcoes (46 arquivos reescritos na rodada setjmp; +291 do fixpoint).
- `pointer_fixpoint.py`: corrigido para o range real (lia fallback defasado; agora parseia
  `REX_CODE_BASE/SIZE` do PCH) — pass 1: 317 candidatos, 291 aceitos, fixpoint convergiu no
  pass 2. `app/overrides.toml` com 444 entradas.
- `switch_check.py` (primeira vez): 0 truncadas, 0 erradas, 0 perdidas (classe limpa).
- `pointer_audit.py` (primeira vez): 10 vtable-like + 11 built-in-code pendentes de revisao.
- `setjmp 0x83615650` / `longjmp 0x83615920` registrados (shape confirmado) — sem efeito
  neste crash (classe diferente, registro correto pelo guia).
- SDK: paginas recem-comitadas agora zeradas (semantica Xbox) — sem efeito neste crash
  (hipotese stale descartada para este bug com evidencia: crash identico com heap zerado).
- Watchpoint com single-step funcional: escritor do `w1=0x04020000` pego em flagrante —
  `sub_829EF010` (`stb` do byte de cor +5 do no, recoloracao de RB aparentemente legitima).
  Guspe: o no e da propria arvore (link valido); o vec le `[x+4]`-como-link e quebra.
  Proxima pergunta: entradas do mantenedor (r3/r28) ou invariante a montante.
- SWITCH (14/10, NRO novo com hooks): `switch/fc3-nx` no SD verificado via DBI/MTP
  (NRO + game_root completo + update/patch.dat+fat + toml com update_data_root + logs OK).
  Crash no console E O MESMO do PC, instrucao por instrucao: `sub_82386818`
  (`fc3_recomp.173.cpp:308`, simbolizado no ELF AArch64), caller `sub_82389218`
  (`fc3_recomp.354.cpp:341`), guest `0x0502FF08`, key `0x0D`, lr guest `0x82373B90`.
  Causa raiz deterministica cross-platform; nao e problema de arquivo no SD.

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