# Far Cry 3 (Xbox 360) -> Nintendo Switch — estado da Etapa 1

Data: 2026-10-10. Projeto em `fc3-nx/`, dados do jogo em `assets/`.

## Onde esta

**Etapa 1 (recompilar e bootar no PC): o crash de memoria foi resolvido. O bloqueio agora e um arquivo
faltando no conteudo do jogo.**

| Etapa | Estado |
|---|---|
| Extrair o jogo | **feito** (5,77 GB, 103 arquivos) |
| Traduzir o codigo do convidado | **feito** (883 funcoes, 469 MB de C++) |
| Compilar o PC | **feito** (`fc3.exe`, 170 MB) |
| Ambiente de build | **montado** (VS Build Tools, clang 23.1.3, Python 3.13, devkitA64 16.1.0 + libnx) |
| Bootar no PC | **em andamento**: passa do crash `0x13C`, monta timer/interrupto, para em `update:\patch.dat` |
| Etapa 2 (renderer nativo Vulkan) | nao comecada |
| Etapa 3 (NRO para o Switch) | CMake/toolchain-file/scripts **prontos**; **nunca compilado** (`out/nx` nao existe). Depende do `libvulkan.a` do NVK, cujo build ainda falha |
| Etapa 4 (desempenho) | nao comecada |

### Ambiente resolvido (2026-10-10, 23:00)

A maquina nao tinha toolchain nenhuma.Instalado e verificado:

| | |
|---|---|
| VS 2022 Build Tools (C++ x64) | `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools` |
| LLVM | `C:\Program Files\LLVM` — clang 23.1.3 |
| Python | `C:\Users\barba\AppData\Local\Programs\Python\Python313` (3.13.15) |
| CMake + Ninja | os do proprio VS Build Tools (3.31.6 / 1.12.1) |
| devkitA64 + libnx | `C:\devkitPro` (junction para `C:\msys64\opt\devkitpro`), GCC 16.1.0, libnx 4.12.0 |

O `MSYS2.MSYS2` do winget instala com `0xC0000135` nesta maquina; o `msys2-base-*.tar.xz` do GitHub
funciona e foi ele que foi usado. O repositorio do devkitPro precisa da chave
`BC26F752D25B92CE272E0F44F7FD5492264BB9D0` e tambem da `62C7609ADA219C60` (que o `pacman` pede para o
`switch-dev`), e o gpg do MSYS2 **nao alcanca o keyserver** — baixe as chaves com o PowerShell e
`pacman-key --add`. Detalhes em `NOTAS-DE-BUILD.md` §11.

O junction `fc3-nx\assets` foi refeito (`cmd /c mklink /J fc3-nx\assets ..\assets`) e `out\pc` foi
apagado e reconfigurado, porque o `CMakeCache.txt` apontava para o caminho antigo do projeto.

### Duas armadilhas do build que custaram tempo

1. **Apos rodar o codegen, o build para.** `cmake --build out\pc` roda o passo `Generating recompiled
   code for fc3`, planeja os 443 passos restantes e sai com codigo 0 **sem compilar nada nem relinkar
   `fc3.exe`**. Nao e erro: o ninja replaneja e para. A saida e `cmake --build` logo depois de rodar o
   configure. Para ver o que ele quer fazer, `ninja -C out\pc -n -d explain`.
2. **`tools\win\env.ps1` nao achava o Python.** O primeiro `python` no PATH e o alias da Microsoft
   Store, que abre a loja em vez de rodar, e `post_codegen.py` falha sem traceback. O `env.ps1` agora
   poem o interpretador real na frente do PATH.

### build_nvk.ps1 e build_switch.ps1

Os dois apontavam para o layout antigo do devkitPro (`<DEVKITPRO>\msys2\...`, que o instalador atual
nao cria). Corrigidos para sondar `C:\msys64` tambem. O `make.exe` que o LTO precisa nao vem no MSYS2
base — e o pacote `make` do pacman.

## O boot, ate onde chega

`out/pc/logs/fc3_006.log` (2026-10-10 23:25), depois da correcao do crash `0x13C`:

```
Function table initialized for module: code=82340000-83DF2AF4, image=82000000-84060000
SDL input driver initialized successfully
Initializing shader storage for title 5553088C...
[gpu] SetInterruptCallback(8365B5A0, 4003E980)      <- timer/interrupto montado
[error] [krnl] XamShowDirtyDiscErrorUI called!      <- e para aqui
```

O crash de `0x13C` foi resolvido (ver `DIAGNOSTICO-BOOT-0x13C.md`). O bloqueio agora e
`update:\patch.dat`: o jogo le esse arquivo no inicio da inicializacao de conteudo e chama
`XamShowDirtyDiscErrorUI` quando ele falta. Ele existe no console (particao de update) mas **nao esta
no ISO extraido** — nenhum dos 17 `.fat` de `assets/game_root` o lista.

Montar o dispositivo resolve metade: com `REX_update_data_root=<pasta>` o log passa a dizer
`mounted ... at \Device\Harddisk0\PartitionUpdate`, e o jogo ainda chama `XamShowDirtyDiscErrorUI`,
porque o que ele quer e o arquivo.

O crash antigo esta em `sub_8237E408`, `fc3_recomp.347.cpp:319`, um `lwz r11,316(r28)` em que `r28` vale zero.

Seis threads leem exatamente `0x13C` no mesmo instante: nao e corruption de registrador, e um **campo global
de sistema que o kernel do Xbox deveria ter escrito e nao escreveu** (o jogo le em varias threads logo apos a
inicializacao de conteudo). `0x13C = 0x13C` e um offset de estrutura, nao um endereco de codigo, o que confirma.

**E o proximo passo da Etapa 1**: descobrir qual export de kernel/XAM escreve esse campo. O caminho e o mesmo do
sa2-nx: ou uma export de kernel que o SDK nao implementa (e que se declara em `app/overrides.toml`/stubs), ou um
`setjmp`/`longjmp` faltando, ou uma funcao alcancada so por ponteiro. O guia, capitulo 3.2, lista as ferramentas
(`tools/find_gaps.py`, `tools/pointer_audit.py`, `tools/switch_check.py`).

### Causa raiz (2026-10-10, ver `DIAGNOSTICO-BOOT-0x13C.md`)

**Corrigido.** A suspeita de `sub_8362B1C0` abaixo estava errada e foi substituida pela analise completa.

O que vale reter:

- `0x13C = 316`, e `316` e exatamente o displacement de `lwz r11,316(r28)`. Logo **`r28 = 0`**, e nao um
  campo global nao inicializado.
- O `r28` de origem e `0x83E1A148` (o `0x8237A148` deste arquivo tem os digitos trocados).
- `r28` e destruido dentro do loop por `sub_8363CE50` (`fc3_recomp.325.cpp:28199`), que faz
  `ld r28,264(r3)` sem prologo e termina em `b` para `__imp__KeSetCurrentStackPointers`.
- A export `KeSetCurrentStackPointers` (`sdk/src/kernel/xboxkrnl/xboxkrnl_threading.cpp:270`) retorna ao
  guest; no hardware ela nao retorna, porque o thread e despachado. O fluxo do guest continua num
  ponto em que so faz sentido depois de um despacho, com `r28` valendo um campo de contexto de thread
  que seis threads leem vazio no mesmo instante.
- `sub_8237E408` esta **correto** quanto a ABI: `__savegprlr_27` salva `r27..r31`, nao `r14..r27`.

Leitura completa, com numeros de linha e as tres correcoes propostas: `DIAGNOSTICO-BOOT-0x13C.md`.

## O que ja da para dizer

**O `default.xex` do Far Cry 3 e gerenciavel.** 12 MB comprimidos, 32 MB descomprimidos, 883 funcoes — menor
que o do Sonic Adventure 2 (39 MB, ~500 correcoes manuais no manifest). A Etapa 1 e viavel.

**Um unico modulo de codigo.** Nenhuma assinatura de XEX dentro de `ige.dat`, `startup.dat` ou `common.dat`: todo
o codigo esta no `default.xex`. O `UplayBrowser.xex` e de outro title.

**Os shaders do jogo vem prontos.** `shadersobj.dat` tem 9 MB de containers Xenos, o que deve cortar bastante o
trabalho do capitulo 6 do guia (Etapa 2).

## Problema aberto

`fc3_recomp.326.cpp` tem 18 branches de `sub_83493B70` para `0x83494044`/`0x83494048`, e o gerador nao emite
esses rotulos: `error: use of undeclared label 'loc_83494048'`.

Causa: `codegen.partition.json` põe esses enderecos sob `sub_83493D58`, que nunca foi gerada. Nao da para consertar
no arquivo gerado (o `.cpp` nao guarda o endereco de cada instrucao, entao a posicao do rotulo e irrecuperavel).
Correcao em teste: declarar `0x83493D58` com `end = 0x83494068`.

Ferramenta de diagnostico: `tools/fix_missing_labels.py`.

## Custos medidos

| | |
|---|---|
| Codegen (analise do XEX) | ~29 min por rodada |
| Build do SDK + gerador | ~15 min (`-j 24`) |
| Rodadas de codegen ate agora | 6 |

Cada rodada reanalisa o XEX inteiro. Vale agrupar correcoes antes de rodar. E o build do PC re-executa o gerador
sozinho quando um input muda, custando 29 min sem avisar.

## Proximos passos

1. `tools/fix_missing_labels.py` deve dizer "nothing missing".
2. `cmake --build out/pc` — compilar os 438 arquivos gerados.
3. `tools/win/boot_test.ps1` — primeiro boot. O log diz onde para.
4. A partir dai e o loop do guia: cada "unregistered call" e um `overrides.toml` novo, rodando o codegen entre um
   e outro.

## Aviso honesto sobre o tamanho

A Etapa 1 e a unica que da para dimensionar agora. A Etapa 2 nao: o renderer nativo em `app/src/me` tem os
enderecos de Direct3D do SA2 hardcoded e precisa ser readaptado ao build de XDK do FC3, e o guia diz que essa e
a parte mais cara. O jogo e um FPS de mundo aberto com streaming, fisica e 1080p — o mesmo codigo que roda o
Sonic Adventure 2 a 60 FPS no Switch vai carregar muito mais aqui.