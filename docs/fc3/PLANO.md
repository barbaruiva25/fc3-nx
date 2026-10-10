# Far Cry 3 (Xbox 360) -> Nintendo Switch

Port estático por recompilação, seguindo o método de `sa2-nx` / `nfsmw-nx` / `masseffect-nx`.

Este arquivo e o plano de trabalho. O guia original do sa2-nx esta em `_base_sa2_nx/docs/porting-guide.md`.

## O jogo

| | |
|---|---|
| Fonte | `Far Cry 3 [MULTI][XBOX360][Region Free][XDG3].iso` (8,15 GB, DVD dupla camada) |
| Engine | Dunia 2 (Ubisoft Montreal) |
| Titulo | Far Cry 3, 2012, retail (XDG3, region free) |
| Formato | Jogo de disco (GoD), nao e XBLA |

Diferencas em relacao ao SA2, que definem o custo de cada etapa:

- SA2: XEX de 10 MB, 1822 arquivos, engine Ninja/GameCube, quase 2D.
- FC3: XEX muito maior, ~8 GB de dados, streaming de mundo, fisica, camera, multiplayer online, 1080p.
- O guia chama de "a parte dificil" justamente o que aqui e maior: cobertura de shaders, transliteracao do Direct3D, custo por draw.

Consequencia pratica: o metodo e o mesmo, mas cada estagio custa muito mais. Nao ha atalho para o renderer nativo.

## Etapa 1: recompilar e bootar no PC

Objetivo: o jogo abrir no PC, com o GPU emulado do SDK, ate um menu.

1. Extrair o ISO (`tools/extract_iso.py`).
2. Identificar `default.xex`: base, entry point, tamanho da imagem, versao XEX, build do XDK.
3. Procurar modulos de codigo extra (DLLs de convidado `*.xex` carregadas com `XexLoadImage`). O guia avisa que o alcance estatico nao ve ponteiros/vtables.
4. Gerar o manifest, rodar `rexglue codegen`.
5. Compilar para Windows e rodar o loop de boot.
6. Corrigir o que a traducao perde (funcoes, jump tables, gaps, setjmp/longjmp, noreturn), com evidencia no manifest.

## Etapa 2: renderer nativo no PC

Objetivo: desenhar com Vulkan em vez do Xenos emulado.

**Atencao: o renderer em `app/src/me` veio do SA2 e tem o endereco do Direct3D do SA2 dentro.** Nao e
reutilizavel como esta. Enderecos do SA2 que precisam ser rediscovered no XEX do FC3:

| Onde | Endereco do SA2 | O que e |
|---|---|---|
| `app/src/me/fc3_d3d_api.cpp:154` | `0x8200070C` | campo do device lido no census |
| `app/src/me/fc3_d3d_api.cpp:268` | `0x82565758` | funcao de D3D hookada no census |
| `app/src/me/fc3_api_internal.h` | tabela de offsets do device | layout do device por build do XDK |
| `app/src/me/fc3_me_hooks.cpp` | enderecos dos Draw*/CreateVertexShader/flip | hooks que o renderer exige |

Metodo (cap. 5.2 e 10.3 do guia):

1. `tools/d3d_match.py` contra um jogo cujos funcoes do XDK sao conhecidos; confirmar com `tools/listing_diff.py`.
2. Census em run time (`fc3_diag_d3d_census`): quais funcoes de D3D o jogo chama de verdade, e quais delas
   escrevem PM4 por frame. No SA2 foram 109 chamadas, 14 escrevendo PM4.
3. Traduzir os shaders ate o log dizer 0 cargas nao identificadas.
4. Comparar frame a frame com o GPU emulado.

Vantagem especifica do FC3: `shadersobj.dat` tem 9 MB de containers de shader do proprio jogo, o que deve
cortar bastante o trabalho do capitulo 6 do guia.

## Etapa 3: Switch

- devkitA64 + libnx + NVK do mesa-switch.
- Camada Horizon do SDK, asset pack, logica de input, display.
- Lancar com forwarder de 39 bits ou title override (modo applet nao tem memoria suficiente).
- O jogo pede mais memoria que um homebrew recebe em modo apelet, e o FC3 pede mais que o SA2.

## Etapa 4: desempenho

- Medir no console (o PC nao diz quanto custa no A57).
- Otimizacoes de codegen, LTO, PGO, funcoes quentes como nativas.
- Otimizacoes de GPU, uma de cada vez, todas pixel-identicas.

## Estado atual

### Feito

- [x] ISO identificado: 8,15 GB, XDG3 (DVD de camada dupla), PT-BR.
- [x] **XEX analisado** (via `tools/extract_iso.py`):

  | | |
  |---|---|
  | Title ID | `5553088C` |
  | Media ID | `6F6EAD36` |
  | Versao | `0.0.0.2` |
  | Image base | `0x82000000` |
  | Entry point | `0x82342D50` |
  | Image size | 33.947.648 bytes |
  | Criptografia / compressao | AES-128 / LZX |
  | Stack padrao | 262.144 bytes |

  O XEX do FC3 (32 MB descomprimido) e **menor** que o do SA2 (39 MB). Todo o peso do jogo esta nos `.dat`.

- [x] Jogo extraido: `assets/game_root`, 103 arquivos, 5,77 GB.
- [x] Ferramentas: LLVM clang 23.1.3 (winget), VS Build Tools 2022, devkitPro/devkitA64/libnx (ja instalados), 7-Zip, WinRAR.
- [x] SDK ReXGlue configurado (`out/host`), gerador `rexglue` compilado.
- [x] Projeto `fc3-nx` criado a partir do sa2-nx: 195 arquivos renomeados de `sa2` para `fc3`, SDK e ferramentas preservados.
- [x] **Traducao concluida**: `rexglue codegen` passou na validacao e escreveu **883 funcoes**
      (469 MB de C++ em `app/generated/default/`) em 1731 s.
- [x] Nenhuma funcao nativa do SA2 sobrando: `app/src/cpu/hot/localized.txt` e os `n_*.h` (motor Ninja,
      CRT e vertex loaders do SA2) foram removidos. O mecanismo esta intacto e vazio, esperando o perfil do FC3.
- [x] **Bug do epilogo compartilhado resolvido**: 18 branches de `sub_83493B70` para o epilogo de
      `sub_83493D58` (outro arquivo) viraram chamadas a uma funcao. Ver `docs/NOTAS-DE-BUILD.md`, secao 9.
- [x] **PC compila**: `fc3.exe`, 162 MB. O renderer nativo e os hooks de D3D do SA2 ficaram fora do build
      (`fc3_BUILD_NATIVE_RENDERER`, OFF), porque hookam enderecos que o FC3 nao tem.
- [x] **Primeiro boot**: o jogo monta os arquivos, a tabela de funcoes (code 82340000-83DF2AF4) e o armazenamento
      de shaders, e para em `Unresolved call from 0x8362B300 to 0x8363CE50`.

### Pendente

- [~] Rodada 7 de codegen: `0x8363CE50` (o unico "unresolved function" que o gerador reportava desde o inicio
      sem contar como erro) registrado no manifest a partir do log do primeiro boot.
- [ ] Loop de boot: cada "unresolved call" e uma entrada nova no manifest e mais uma rodada de 30 min.
- [ ] `glslangValidator` ja instalado. Renderer nativo (Etapa 2): redescobrir os enderecos de Direct3D do FC3
      (os 16 do SA2 estao listados em `docs/PLANO.md`).
- [ ] Compilar o **NVK** (driver Vulkan do Switch, `libvulkan.a`): repo `danfromtico/mesa-switch` no commit
      `1a8c1a66d6f` (o `main` atual nao tem o NVK), com o patch do nfsmw-nx. Ver `tools/win/build_nvk.ps1`.
- [ ] Build do NRO para o Switch (Etapa 3).
- [ ] Desempenho (Etapa 4).

### Variaveis de custo da Etapa 1

Medidas reais desta rodada, uteis para estimar as proximas:

| | |
|---|---|
| Codegen completo (analise do XEX) | **~29 min por rodada** |
| Build do SDK + gerador (primeira vez) | ~15 min com `-j 24` |
| Rodada 1: funcoes nao alcancadas | 20 erros / 17 alvos |
| Rodada 2: funcoes nao alcancadas | **1 erro** (o vizinho `0x837B3858` do `0x837B3848`, revelado ao registrar o primeiro) |
| Rodada 3: validacao passou | 883 funcoes escritas; apareceu `use of undeclared label` ao compilar |
| Rodada 4: `sub_83493D58` declarado sem `parent` | nao resolveu (a funcao continua fora da arvore) |
| Rodada 5: `sub_83493D58` como chunk (`parent`) | em curso |

O padrao que emerge: cada `overrides.toml` novo revela vizinhos. O do SA2 tem ~500 entradas depois de varios
boots; o FC3 comeca em 18. **A cada rodada a analise do XEX inteiro e refeita (29 min), entao vale agrupar as
correcoes antes de rodar de novo.** E o build do PC re-executa o gerador sozinho quando um input muda, o que
custa outros 29 min sem avisar.

### Modulos de codigo: resolvido

Procurado o magic `XENO` (inicio de um XEX) em `ige.dat`, `startup.dat` e `common.dat`: **zero ocorrencias**.
Nao ha modulo de codigo embutido nesses containers, entao o jogo inteiro esta no `default.xex` e a Etapa 1
precisa de **um unico modulo**. Ainda falta confirmar no log do primeiro boot (o jogo pode carregar um
`UplayBrowser.xex` separado, que e de outro title).

## Estrutura do jogo (achados)

O jogo nao tem milhares de arquivos soltos: tudo esta em pares `.dat`/`.fat` (tabela de arquivos da Ubisoft).

| Arquivo | Tamanho | Conteudo provavel |
|---|---|---|
| `default.xex` | 11,5 MB | codigo do jogo (PPC) |
| `ige.dat` | 39,3 MB | **codigo do motor da Ubisoft** (candidato a modulo `[[modules]]`) |
| `shadersobj.dat` | 9,0 MB | **pacote de shaders do jogo** (Xenos microcode) |
| `startup.dat` | 13,4 MB | dados de boot |
| `common.dat` | 155,8 MB | assets compartilhados |
| `sound.dat` | 525,4 MB | audio |
| `worlds/fc3_main/` | ~2,3 GB | mundo principal |
| `worlds/multicommon/` | ~2,1 GB | mundo compartilhado |
| `UplayBrowser.xex` | 5,0 MB | overlay Uplay (outro title, nao e o jogo) |

Consequencias praticas:

1. **`shadersobj.dat` e um presente**: 9 MB de containers de shader prontos, o que reduz muito o
   trabalho do capitulo 6 do guia (traducao XenosRecomp -> HLSL -> DXC -> SPIR-V).
2. **O `ige.dat` precisa ser investigated**: se o jogo o carrega com `XexLoadImage`, ele entra no manifest
   como `[[modules]]`. Sem isso o port para no entry point. O log do primeiro boot responde isso.
3. **Idioma**: este ISO e PT-BR, e o jogo tem o Portuguese do Brasil na lista dele (a string `pTBr` esta no
   `common.dat`). Mas **todos os `sound_<idioma>.dat` estao com 0 bytes**: o audio esta todo em `sound.dat`
   (525 MB). Como fica a selecao de idioma (e se o jogo aceita PT-BR sem os arquivos separados) e coisa a
   descobrir no boot e no log.

## Controles (previsto)

O SDK mapeia HID para XInput por jogador, com Joy-Cons deitados. Para um FPS:

- stick esquerdo: movimento; stick direito: camera.
- Botao inferior (A do Xbox) = pulo/recuo,right = mira, como no pad do 360.
- Touch: botoes de mira/disparo e controles de veiculo.
- Genericos: Switch Pro Controller e qualquer pad com HID.

O mapeamento exato depende do que o jogo le no 360, entao e definido depois que o jogo bootar.