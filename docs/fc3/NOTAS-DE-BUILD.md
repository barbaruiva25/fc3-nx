# Notas de build do fc3-nx

Coisas que quebram na primeira tentativa e como ficaram resolvidas aqui. Nao sao proprias do FC3: valem para
qualquer novo projeto feito a partir do SDK.

## 1. `out/host` precisa de `-march=x86-64-v2`

O SDK usa intrínsecos SSSE3 (`_mm_shuffle_epi8` em `sdk/src/core/memory.cpp`). Configurado sem a flag, o clang
falha com:

```
error: always_inline function '_mm_shuffle_epi8' requires target feature 'ssse3', but would be inlined into
function 'copy_and_swap_16_aligned' that is compiled without support for 'ssse3'
```

Os presets do proprio SDK (`sdk/CMakePresets.json`) ja passam `-march=x86-64-v2`; a instrucao manual do
`docs/building.md` do sa2-nx nao passa. Configurar com:

```powershell
cmake -S sdk -B out/host -G Ninja -DCMAKE_BUILD_TYPE=Release `
      -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ `
      -DCMAKE_C_FLAGS=-march=x86-64-v2 -DCMAKE_CXX_FLAGS=-march=x86-64-v2
```

## 2. O clang da winget precisa do MSVC no PATH

O clang do `C:\Program Files\LLVM` com target `x86_64-pc-windows-msvc` usa `lld-link`, que nao entende as flags
de import library que o check do compilador do SDK passa (`--enable-auto-import`, `--out-implib`), e o
`cmake` falha no teste do compilador. Carregar o MSVC resolve, porque o `link.exe` do VS ganha:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\win\run.ps1 out\env.log "where link"
```

`tools/win/env.ps1` faz isso (via `vcvars64.bat`), e e por isso que todo comando de build passa por
`tools\win\run.ps1`.

## 3. `msys2\usr\bin` no PATH atrapalha

O devkitPro coloca o `C:\devkitPro\msys2\usr\bin` no PATH, que tem o proprio `cmake`, `ninja`, `link` e
`python`. O `link.exe` do MSYS2 e um link para `unlink`, nao o linker. O `env.ps1` tira esse caminho do PATH;
fazendo build fora dele da resultado errado.

## 4. Politica de execucao do PowerShell

`. .\tools\win\env.ps1` e bloqueado pela ExecutionPolicy. Usar sempre
`powershell -NoProfile -ExecutionPolicy Bypass -File tools\win\run.ps1 <log> "<comando>"`, que e a forma que o
proprio repositorio usa.

## 5. `glslangValidator` e obrigatorio antes do build do PC

Os shaders do renderer nativo (`app/src/me/native/shaders/*.comp|frag|vert`) viram inicializadores SPIR-V em
tempo de build. Sem o `glslangValidator.exe` em `out/glslang/StandAlone/`, o `cmake --build out/pc` falha com
`FAILED: generated-shaders/fc3_edram_7e3_to_rgba8.inc` e a mensagem do Windows "O sistema nao pode encontrar o
caminho especificado" (o caminho do executavel que nao existe), **sem nenhum `error:` no log**. Buildar antes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\win\build_glslang.ps1
```

Usa `clang-cl`, nao `clang++`: o glslang passa `-Wl,-undefined,error`, que o `lld-link` recusa.

## 6. `post_codegen.py` pelo Python certo

O `codegen.ps1` chama `python` (o do MSYS2, quando o `env.ps1` nao esta carregado) e falha com um caminho
Windows prefixed por `/home/...`. Rodar a traducao pelo `run.ps1`; se o `post_codegen` falhar, chamar direto:

```powershell
$env:REXSDK_DIR = '<repo>\sdk'; py -3 tools\post_codegen.py
```

## 7. Os dados do jogo fora do repositorio

O `codegen.ps1` procura `assets\game_root\default.xex` dentro do projeto, mas o ISO extraido tem 5,77 GB e o
`.gitignore` ja manda ignorar `/assets/`. Para nao duplicar, `fc3-nx\assets` e um junction para
`..\assets`. O `app/fc3_manifest.toml` aponta para `../../assets/game_root` (caminho real), e o `codegen.ps1`
encontra pelo junction.

## 8. Renomear sa2 -> fc3

`app/src` tem 57 arquivos e `app` + `tools` tem 195 arquivos de texto com `sa2`/`SA2`/`Sa2` no nome ou no
conteudo. A conversao do texto e mecanica (substituicao textual), mas as analises especificas do SA2 precisam
sumir, porque apontam para enderecos que o FC3 nao tem:

| Arquivo | O que era do SA2 |
|---|---|
| `app/overrides.toml` | ~500 funcoes do XEX do SA2 (substituido por 18 do FC3) |
| `app/src/cpu/hot/localized.txt` | 100+ funcoes quentes do SA2 (motor Ninja, CRT) |
| `app/src/cpu/hot/n_*.h` | as versoes escritas a mao delas |
| `app/src/cpu/fc3_hot_guest.cpp` | os hooks que registravam essas funcoes |
| `app/hot_functions.ld` | a ordem de `.text` vinda do perfil do SA2 |
| `pgo/` | perfil do SA2, que so vale para o codigo dele |

Erro de ambiente que custa tempo: o `-Include` do PowerShell em `Get-ChildItem` com caminho curto as vezes nao
filtra nada, e da a impressao de que a substituicao textual falhou. Filtrar por
`Where-Object { $ext -contains $_.Extension }` e confiavel.

## 9. Rotulos perdidos: `use of undeclared label` e um epilogo compartilhado

O gerador emite `goto loc_<addr>:` para todo alvo de `b`/`bc` que coleta, mas so escreve `loc_<addr>:` onde um
bloco **comeca** naquele endereco. Quando o bloco alvo esta em **outra funcao**, o `goto` sai e o rotulo nao.

No FC3 sao 18 branches de `sub_83493B70` para `0x83494044`/`0x83494048`, que sao o **epilogo** de
`sub_83493D58` (outro arquivo, `fc3_recomp.66.cpp`):

```
fc3_recomp.326.cpp:26796:24: error: use of undeclared label 'loc_83494048'
```

Um `b` para um epilogo compartilhado e normal em PowerPC: o compilador do Xbox layout o assim. C++ nao consegue
saltar para dentro do bloco de outra translation unit.

**Correcao (tres ferramentas, todas idempotentes, agora em `post_codegen.py`):**

1. `tools/fix_cross_file_labels.py` — envolve o bloco em `void fc3_label_<hex>(ctx, base) { ... }` no arquivo que
   o possui.
2. `tools/lift_label_wrappers.py` — **sobe o wrapper para o topo do arquivo**. Sem isso ele fica dentro de
   `DEFINE_REX_FUNC(sub_83493D58) { ... }` e o clang diz `function definition is not allowed here`.
3. `tools/fix_cross_file_branch_sites.py` + `tools/fix_cross_file_branch_calls.py` — reescrevem
   `goto loc_X;` em `if (cond) { fc3_label_X(ctx, base); return; }`.

O `return` depois da chamada e o que torna exato: o bloco e o epilogo do chamada (restaura f30/f31, `__restgprlr`,
volta ao chamador do convidado), entao o controle nao pode voltar para a instrucao seguinte ao branch. A ferramenta
decide por wrapper, olhando a ultima sentencia do corpo.

Erros que aparecem se a ordem for errada, para nao se perder:

| Sintoma | Causa |
|---|---|
| `use of undeclared label 'fc3_label_X'` | o wrapper foi criado mas nao elevado, e o `goto` fica antes da declaracao |
| `function definition is not allowed here` | o wrapper ficou dentro de outra funcao (falta o passo 2) |
| `expected ';' after goto statement` | sobrou `goto f(ctx, base);` — `goto` aceita label, nao chamada (falta o passo 3) |
| `call to 'fc3_label_X' is ambiguous` | declaracao duplicada, uma com `extern "C"` e outra sem |

Nao e possivel consertar no `.cpp` gerado sem mais contexto: ele nao guarda o endereco de cada instrucao (o comentario
guarda o mnemonico, nao o endereco). O caminho e o manifest + estas tres ferramentas.

## 10. O NVK precisa de dois headers que o commit nao traz

O commit `1a8c1a66d6f` do `danfromtico/mesa-switch` (o que o nfsmw-nx usa) tem o codigo do NVK e do
`nvkmd/switch`, mas o `winsys/nouveau/switch` dele foi escrito contra uma API de `nouveau_device_new` de **2
argumentos**, e o codigo chama com **5**. Compilar assim da:

```
nouveau_winsys.h:198: error: too many arguments to function 'nouveau_pushbuf_kick'; expected 1, have 2
nouveau_switch_winsys.c:53: error: too many arguments to function 'nouveau_device_new'; expected 2, have 5
```

O commit que traz os headers compativeis e `e008cab0413` ("carry the libdrm_nouveau headers the OpenGL winsys
implements"), que e **anterior** ao que usamos, entao o checkout novo nao os tem:

```sh
git show e008cab0413:src/gallium/winsys/nouveau/switch/nouveau.h     > src/gallium/winsys/nouveau/switch/nouveau.h
git show e008cab0413:src/gallium/winsys/nouveau/switch/nouveau_drm.h > src/gallium/winsys/nouveau/switch/nouveau_drm.h
```

E o `-I` do cross file aponta para `.../winsys/nouveau/switch`, **nao** para `.../winsys/nouveau/drm`: existe um
`nouveau.h` tambem no `drm/`, e ele e o da API antiga, que e o que produz os erros.

Outras opcoes que nao servem neste commit:

| Opcao | Resultado |
|---|---|
| `-Dvulkan-drivers=nvk` | `not in allowed choices` (o NVK nao e uma opcao aqui; ele e o driver do `nvkmd/switch`, o meson acha sozinho) |
| `-Dgallium-drivers=none` | `not in allowed choices` |
| `-Dgallium-drivers=softpipe` | `src/egl/meson.build:157: Switch EGL requires the nouveau Gallium driver` |

Ou seja: `-Dplatforms=switch -Dgallium-drivers=nouveau`, sem `-Dvulkan-drivers`.

### Onde o build do NVK parou, e por que

O commit `1a8c1a66d6f` e **internamente inconsistente**: o `winsys/nouveau/switch` foi escrito contra uma
versao do `nouveau.h` diferente da que o resto da arvore traz. Resolver os headers foi possivel (commit
`e008cab0413` + `-I` na ordem certa + includes por caminho explicito), mas depois aparecem conflitos de tipo
entre `src/gallium/drivers/nouveau/nouveau_winsys.h` (que usa a API do `drm/`) e o `winsys/switch`:

```
nouveau_winsys.h:82:6: error: conflicting types for 'nouveau_switch_pushbuf_set_fence_batch_notify'
nouveau_winsys.h:87:10: error: conflicting types for 'nouveau_switch_pushbuf_batch_generation'
nouveau_switch_winsys.c:176:40: error: passing argument 1 of 'nouveau_pushbuf_bind_context' from
                                 incompatible pointer type
```

Ou seja: o driver de Gallium do Switch, no commit, nao compira contra os headers que a arvore tem. **O caminho
para o NVK nao e o Gallium nouveau** — o NVK (`src/nouveau/vulkan/`) e que a Etapa 3 precisa, e ele compila
sozinho; o Gallium so e exigido porque `src/egl/meson.build` do Switch o declara obrigatorio
(`Switch EGL requires the nouveau Gallium driver`).

Proximas tentativas, em ordem de custo:

1. `-Dplatforms=surfaceless` (ou `auto`) em vez de `switch`: tira o EGL do Switch do build, que e a unica coisa
   que puxa o Gallium. O NRO do fc3-nx usa NWindow, entao talvez falte algo, mas vale medir antes.
2. `-Dwith_egl=false` / `-Dgles1=false -Dgles2=false -Dopengl=false`, se as opcoes existirem neste commit.
3. Um commit mais novo que tenha o `winsys/switch` e o `nouveau.h` coerentes: procurar
   `git log --all -- src/gallium/winsys/nouveau/switch/` e testar `d62fc66b251` ("Clean up Switch port code"),
   que vem depois de `1a8c1a66d6f`.

O patch do nfsmw-nx (35 arquivos) aplica limpo em `1a8c1a66d6f`; se a solucao for mover de commit, ele pode
precisar de `git apply --3way`.

### Detalhe que custou tempo: o PowerShell grava UTF-16

```powershell
git show e008cab0413:path > file     # BOM FF FE, UTF-16
```

O clang le BOM UTF-16 como `stray '\377' in program`. Ao gravar arquivo com redirecionamento do PowerShell,
converter antes (`[System.IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false))`), ou
usar `git show ... | Out-File -Encoding utf8`.

### O que ja foi tentado para `sub_83493D58`, e por que nao resolveu

| Tentativa | Resultado |
|---|---|
| `"0x83493D58" = { }` | nao e gerada |
| `= { parent = 0x83493B70 }` (chunk) | nao e gerada |
| `= { end = 0x83494068 }` (tamanho explicito) | nao e gerada |
| `sub_83493B70` com `end = 0x83493D58`, para tirar o branch da regiao PDATA | nao e gerada |

Quatro rodadas de codegen, ~30 min cada, sem resolver. O filtro esta antes de onde a leitura do codigo sugere.

O que o codigo mostra:

- `phase_register.cpp` (~linha 550) cria a funcao no grafo com `FunctionAuthority::CONFIG` e o tamanho do
  manifest; `phase_discover.cpp` (69-73) usa esse tamanho para CONFIG em vez do PDATA. Com `end` declarado, o
  tamanho existia e a funcao ainda nao apareceu.
- `phase_discover.cpp` linha 175, `if (!isCall && target >= funcAddr && target < pdataEnd) continue;`, descarta o
  branch. Dar `end` a `sub_83493B70` foi calculado para tirar o branch de `pdataEnd`, e nao resolveu — o que
  significa que `pdataEnd` vem do PDATA do XEX e ignora o `end` do manifest para funcoes CONFIG nesta fase.

Onde olhar a seguir: `phase_register.cpp` linha 550 (`graph.addFunction`) e o que acontece entre ele e o Discover
— se a funcao CONFIG e registrada mas nunca entra na lista de "pending" que o Discover expande, o sintoma e
exatamente este.

Como de contornar sem mexer no SDK (ainda nao testado): `tools/read_before_write.py` e as ferramentas de pointer nao
se aplicam aqui, porque o problema e descoberta de funcao, nao analise de ponteiro. A opcao e patch no
`phase_discover.cpp` para que branches internos que o PDATA joga dentro da propria regiao ainda virem
`addUnresolvedJumpToFunction` quando o endereco alvo nao for coberto por nenhum bloco ja descoberto.

## 11. Instalar o ambiente na mao (2026-10-10)

O `MSYS2.MSYS2` do winget termina com `0xC0000135` nesta maquina. O `msys2-base-<data>.tar.xz` do
GitHub funciona:

```powershell
$ProgressPreference='SilentlyContinue'
Invoke-WebRequest https://github.com/msys2/msys2-installer/releases/download/<data>/msys2-base-x86_64-<data>.tar.xz -OutFile msys2-base.tar.xz
tar -xJf msys2-base.tar.xz -C C:\          # cria C:\msys64
```

`pacman-key --init` precisa de varias tentativas: o keyserver falha de forma intermitente. O
`devkitPro` precisa de duas chaves que o MSYS2 **nao consegue buscar** (o gpg dele nao alcanca o
keyserver, embora o PowerShell alcance):

```powershell
foreach($k in @('BC26F752D25B92CE272E0F44F7FD5492264BB9D0','62C7609ADA219C60')){
  Invoke-WebRequest "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$k" -OutFile "C:\msys64\home\barba\dkp-$k.asc"
}
bash -lc "pacman-key --add ~/dkp-*.asc; pacman-key --lsign BC26F752D25B92CE272E0F44F7FD5492264BB9D0"
```

O `HOME` do MSYS2 e `/home/<usuario>`, nao `/home/` — copie as chaves para `C:\msys64\home\<usuario>\`,
senao `~/dkp-key.asc` nao existe e o erro e "No such file or directory" sem dizer qual arquivo.

Depois: os repositorios em `/etc/pacman.conf` (`[dkp-libs]` + `[dkp-windows]`, este ultimo com
`x86_64` literal, **nao** `$arch` — o `$arch` do PowerShell e expandido antes de chegar no bash), o
pacote `make` (o MSYS2 base nao traz), e por fim `pacman -S switch-dev`.

O instalador do devkitPro hoje poe tudo em `C:\msys64\opt\devkitpro`, entao `C:\devkitPro` precisa ser
um junction para esse caminho: os scripts do repositorio (§10, `build_switch.ps1`) assumem o layout
antigo, onde o MSYS2 ficava em `<DEVKITPRO>\msys2`. Os dois scripts foram corrigidos para sondar os
dois layouts, mas o junction tambem e o que faz o `switch-devkitA64.cmake` achar o `DEVKITPRO` sem
`-D` na linha de comando.

## 12. O build do PC para depois do codegen (2026-10-10)

`cmake --build out\pc` roda o passo `Generating recompiled code for fc3`, **planeja os 443 passos
seguintes e sai com codigo 0 sem compilar nada nem relinkar `fc3.exe`**. Nao ha erro no log: o ninja
replaneja depois do passo de codegen e para ali.

O que faz funcionar e rodar o configure depois do codegen:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\win\run.ps1 out\pc_configure.log "cmake --preset win-pc -S app"
powershell -NoProfile -ExecutionPolicy Bypass -File tools\win\run.ps1 out\pc_build.log "cmake --build out\pc -j 32"
```

O sintoma e silencioso e enganoso: um `fc3.exe` antigo continua no lugar, com o timestamp velho, e o
`boot_test.ps1` roda esse binario velado e da a impressao de que a mudanca nao teve efeito. Confira
sempre o timestamp de `out\pc\fc3.exe` depois de um patch. Para ver o que o ninja quer fazer:

```powershell
ninja -C out\pc -n -d explain          # planeja, nao executa
```

E o `env.ps1` ganhou o Python: o primeiro `python` no PATH e o alias da Microsoft Store, que abre a
loja em vez de rodar, e `post_codegen.py` falha sem traceback util.

## 13. O build do NVK: o que travava de verdade (2026-10-11)

A §10 deste arquivo descrevia o build do Mesa parando em conflito de tipos no `nouveau_switch_winsys.c`.
**Esse conflito ja nao existe** — o patch nfsmw traz a assinatura certa e o `nouveau_screen.h:145` casa
com a chamada. O que travava mesmo eram quatro coisas, nesta ordem.

### 13.1 `byacc` nao existe no MSYS2

`meson.build:2243` procura `byacc` **so depois de** `bison` (linha 2240). Bastava `bison` instalado:

```bash
pacman -S --needed --noconfirm bison flex
```

### 13.2 zlib linkado como `.so`

O build do subprojeto zlib falhava com `undefined reference to 'main'`: o meson o montava como
biblioteca compartilhada, e um `.so` cross-compilado nao tem `main`. O NRO precisa de estatico. Em
`nvk_meson_setup.sh`:

```sh
--default-library=static
```

### 13.3 O cross file apontava para a pasta antiga (a causa raiz)

Depois da mudanca do projeto, `mesa-switch/switch_cross_file.txt` continuava com os `-I` absolutos do
caminho antigo. **Um `-I` para um diretorio que nao existe nao da erro: o compilador aceita a flag, o
include so falha depois, e a mensagem parece header faltando:**

```
nouveau_switch_libdrm.h:19: fatal error: winsys/nouveau/switch/nouveau.h: No such file or directory
```

O caminho `/c/Users/...` do MSYS2 **funciona** — o MSYS2 converte para `C:\Users\...` quando lanca o
gcc nativo. O que estava errado era so o caminho. `tools\win\probe_crossfile_paths.sh` prova os dois
fatos.

Confirme sempre com `out\mesa\build.ninja`, que e onde a resposta fica gravada:

```powershell
Select-String -Path out\mesa\build.ninja -Pattern "nouveau_switch_libdrm.c.o:" -Context 0,5
```

### 13.4 `-Reuse` nao relê o cross file

Com `-Reuse`, `meson setup` nao roda e os `c_args` ficam os que estavam no build gerado, **mesmo depois
de editar o cross file**. O ninja ve o cross file mudar e refaz o `configure`, mas isso nao reinsere os
`c_args`. Depois de mexer no cross file, o build tem de ser do zero:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\win\build_nvk.ps1 -Jobs 24     # sem -Reuse
```

### Dependencias do MSYS2 para o Mesa

`tools\win\install_mesa_deps.sh` instala tudo de uma vez. O Python do MSYS2 e PEP 668 (o pip recusa
instalar nele), entao os pacotes Python vem pelo `pacman`: `python-mako`, `python-setuptools`,
`python-markupsafe`, `python-yaml`.

### 13.5 Os headers que discordavam (o Gallium nouveau)

`-I` resolvido, o build chegou no conflito de tipos que a §10 descrevia. **A causa era dupla:**

1. `src/gallium/drivers/nouveau/nouveau_winsys.h` declarava, sozinho, toda a API
   `nouveau_switch_pushbuf_*` — e `src/gallium/winsys/nouveau/switch/nouveau_switch_public.h`
   declara **exatamente as mesmas funcoes, com os mesmos prototipos**. Duas declaracoes de cada funcao
   dao "conflicting types" assim que as duas headers ficam visiveis. A segunda copia foi removida e
   trocada por `#include "winsys/nouveau/switch/nouveau_switch_public.h"`.

2. `nouveau_winsys.h` incluia `winsys/nouveau/drm/nouveau.h` **antes** do header do Switch. As duas
   headers definem `struct nouveau_pushbuf` (e vizinhas) e usam o **mesmo include guard**: ganha a
   primeira, e a segunda e descartada em silencio. Como a do DRM vinha primeiro, todas as structs do
   Switch viravam o layout do DRM — e era isso que produzia a lista inteira de
   `passing argument 1 ... from incompatible pointer type`. O include do DRM agora e
   `#ifndef __SWITCH__`.

### 13.6 O Vulkan nao era habilitado — e o `-D` que faltava

Com os headers resolvidos, o build passou, mas **nao gerou nenhum alvo Vulkan e nenhum
`libvulkan.a`**. O `meson-log.txt` diz:

```
Run-time dependency spirv-tools found: NO
  Vulkan
```

Duas coisas diferentes. A opcao `spirv-tools` e `auto` e `dependency('SPIRV-Tools')` falha sem
aviso (o `wrap` nao existe em `subprojects/`), e o Vulkan inteiro e pulado.

**A correcao esta no proprio `build-switch.sh` do mesa-switch**, que e a receita com que esta arvore
foi feita. As flags que faltavam:

```
-Dvulkan-drivers=nouveau      # sem isso NAO existe alvo Vulkan nenhum
-Degl=disabled -Dopengl=false -Dgles1=disabled -Dgles2=disabled -Dglx=disabled
```

A segunda linha e o que mata o problema do Gallium: `src/egl/meson.build:155` faz `error()` quando a
plataforma e `switch` e o Gallium nouveau nao esta ligado — ou seja, era o EGL que obrigava a metade do
Gallium a entrar no build, e a metade do Gallium e justamente a que os headers nao fecham. Desligando
GL e EGL sobra so a metade Vulkan, que e a unica que o NRO usa.

Note que o valor e **`nouveau`**, nao `nvk`: a §10 deste arquivo diz que o meson rejeita `nvk`, o que
e verdade, mas a flag correta existia e nao estava no `nvk_meson_setup.sh`.

`build-switch.sh` ainda faz um **build nativo** antes, para ter `mesa_clc` e `vtn_bindgen2` no PATH.
Esse passo nao esta aqui: ele exige um LLVM do host casando com o Mesa 26.2, e o NVK nao usa o
caminho do CLC. Se faltar `mesa_clc` no build cross, e esse o proximo passo.