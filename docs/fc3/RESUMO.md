# Far Cry 3 (Xbox 360) -> Nintendo Switch — estado da Etapa 1

Data: 2026-10-09. Projeto em `fc3-nx/`, dados do jogo em `assets/`.

## Onde esta

**Etapa 1 (recompilar e bootar no PC): o jogo compila e faz o boot. O loop de boot esta em andamento.**

| Etapa | Estado |
|---|---|
| Extrair o jogo | **feito** (5,77 GB, 103 arquivos) |
| Traduzir o codigo do convidado | **feito** (883 funcoes, 469 MB de C++) |
| Compilar o PC | **feito** (`fc3.exe`, 162 MB) |
| Bootar no PC | **em andamento**: carrega o jogo, para num campo de sistema ainda zerado |
| Etapa 2 (renderer nativo Vulkan) | nao comecada |
| Etapa 3 (NRO para o Switch) | NVK em compilacao; NRO nao comecado |
| Etapa 4 (desempenho) | nao comecada |

## O boot, ate onde chega

`out/pc/logs/fc3_002.log` (2026-10-10):

```
Function table initialized for module: code=82340000-83DF2AF4, image=82000000-84060000
SDL input driver initialized successfully
Initializing shader storage for title 5553088C...
Unhandled guest access violation: read of guest 0x0000013C on thread 0xF8000060
  (identico em 6 threads, mesmo PC)
```

O crash esta em `sub_8237E408`, `fc3_recomp.347.cpp:319`, um `lwz r11,316(r28)` em que `r28` vale zero.
`r28` vem de `lis r11,-31774` + `addi r28,r11,-24248` = `0x8237A148`, um endereco valido da imagem: o
gerador esta certo, e o mesmo acesso passa nas linhas 256, 267 e 284 da mesma funcao. Entre 284 e 318 ha uma
chamada indireta (`bctrl`), e e depois dela que `r28` aparece zerado.

Seis threads leem exatamente `0x13C` no mesmo instante: nao e corruption de registrador, e um **campo global
de sistema que o kernel do Xbox deveria ter escrito e nao escreveu** (o jogo le em varias threads logo apos a
inicializacao de conteudo). `0x13C = 0x13C` e um offset de estrutura, nao um endereco de codigo, o que confirma.

**E o proximo passo da Etapa 1**: descobrir qual export de kernel/XAM escreve esse campo. O caminho e o mesmo do
sa2-nx: ou uma export de kernel que o SDK nao implementa (e que se declara em `app/overrides.toml`/stubs), ou um
`setjmp`/`longjmp` faltando, ou uma funcao alcancada so por ponteiro. O guia, capitulo 3.2, lista as ferramentas
(`tools/find_gaps.py`, `tools/pointer_audit.py`, `tools/switch_check.py`).

### Suspeita mais especifica (verificada no codigo gerado)

O caminho do crash tem uma anomalia de ABI:

- `sub_8237E408` calcula `r28` de `lis r11,-31774` + `addi r28,r11,-24248` = `0x8237A148` (endereco valido da
  imagem) e o usa em quatro leituras: `lwz r11,316(r28)` nas linhas 256, 267, 284 e 318.
- As tres primeiras passam. A quarta crasha. Entre 284 e 318 ha uma chamada indireta (`bctrl`, linha 296) e
  depois chamadas a `sub_8362B0E0`, `sub_8362B1C0`, `sub_8362B300`.
- **`sub_8362B1C0` faz `mr r28,r4` e nunca salva `r28`** (nem no prologo, nem no epilogo). No PowerPC `r28` e
  non-volatile (r14-r31): quem altera tem de salvar. As funcoes do Xbox compiladas com oCallingConvention do SDK
  usam `__savegprlr_N` justamente para isso, e `sub_8362B1C0` usa `__savegprlr_27` — que salva r14..r27, nao r28.

Se essa leitura estiver certa, `r28` volta de `sub_8362B1C0` com o valor de `r4`, e `r28+316` cai fora da imagem:
o que o log mostra (`guest 0x13C`) e consistente com `r28` pequeno.

Como verificar sem adivinhar: `tools/guest_code_hash.py` e o `register_visitor` do SDK. A pergunta objetiva e
**"essa funcao deveria ter um `__savegprlr_28` (ou `_31`) no XEX e o gerador nao o reconheceu?"**. Duas respostas
possiveis:

- se o XEX tem o save e o gerador nao o detectou, e um caso de `[[functions]]` / assinatura faltando;
- se o XEX nao tem, entao o compilador Xbox otimizoucg knowing que nenhum caller le r28 depois, e quem esta
  errado e o **analise do codegen** (ou o `r28` do chamador e nao na verdade o mesmo registro, porque a chamada
  passa o valor em outro).

Como o codegen traduz `sub_8362B1C0` com `__savegprlr_27` (extraido da assinatura real do XEX), a segunda
hipotese e mais provavel: `sub_8362B1C0` usa `r28` como local **e** o chamador depende dele, o que so compila se
o Xbox soubesse de algo que o codegen nao sabe — tipicamente que `r4` (e portanto `r28`) ja tinha o valor certo,
ou que o caller reatribui `r28` depois. `sub_8237E408` reatribui `r28` na linha 250, antes do loop, mas nao
dentro dele.

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