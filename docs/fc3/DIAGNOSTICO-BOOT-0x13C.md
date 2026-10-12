# Diagnóstico: `Unhandled guest access violation: read of guest 0x0000013C`

Data: 2026-10-10. Substitui a hipótese de `sub_8362B1C0` que estava no `RESUMO.md`
(essa hipótese foi testada e está errada — ver "Hipótese descartada" no fim).

## **RESOLVIDO em 2026-10-10 23:24**

O crash foi corrigido e o boot passou. Ver "A correção" no fim. O bloqueio seguinte é
`update:\patch.dat`, que é um problema de dados, não de emulação.

## O sintoma

`out/pc/logs/fc3_022.log`, 10/10 2026 04:20:50.502-506:

```
[error] [sys] [t92656] Unhandled guest access violation: read of guest 0x0000013C
                      (host 0x000000010000013C) on thread 0xF8000060
[error] [core] [t92656] Unhandled guest access violation at host PC 0x7ff6b0099405
                       (fc3.exe+0x79E9405)
```

Seis threads (`0xF8000060`..`0xF80000B0`), **o mesmo instante**, **o mesmo PC**, **o mesmo endereço**.
O jogo monta o VFS, inicializa a tabela de funções, cria o device D3D12, o SDL e o armazenamento de
shaders, e morre assim que começa a inicializar conteúdo.

## A prova de que `r28` vale zero

O leitor é `lwz r11,316(r28)`, em `fc3_recomp.347.cpp:319`:

```cpp
loc_8237E4A8:
    // lwz r11,316(r28)
    ctx.r11.u64 = REX_LOAD_U32(ctx.r28.u32 + 316);   // <-- crash
```

O endereço no log e no ReXGlue é `r28 + 316`, e `316 = 0x13C`. Logo **`r28 = 0`**: não é um ponteiro
para fora da imagem, é o valor zero. Isso descarta "campo global nunca inicializado" e aponta para
"registrador destruído".

O mesmo `r28` funciona nas leituras das linhas 257, 268 e 285. O valor de origem:

```cpp
// lis r11,-31774              -> r11 = 0x83E20000
// addi r28,r11,-24248         -> r28 = 0x83E1A148
```

(endereço válido dentro da imagem `0x82000000`-`0x84060000`; o `0x8237A148` do `RESUMO.md` tem os
dígitos trocados, o valor real é `0x83E1A148`).

## Onde o `r28` morre

Entre a linha 285 (funciona) e a linha 319 (crash) o fluxo é:

```cpp
// linha 296-298: chamada indireta (bctrl) para a aloca��ão do n��
// linha 315-316: ble -> sai do loop se 308(r31) <= 0
loc_8237E4A8:                                   // linha 317: topo do loop
    ctx.r11.u64 = REX_LOAD_U32(ctx.r28.u32 + 316);   // linha 319: CRASH
    ...
    ctx.lr = 0x8237E558;
    sub_8362B300(ctx, base);                    // linha 413, dentro do corpo do loop
loc_8237E558:
    ctx.r29.s64 = ctx.r29.s64 + 1;              // linha 417
    ctx.cr6.compare<uint32_t>(ctx.r29.u32, ctx.r11.u32, ctx.xer);
    if (ctx.cr6.lt) goto loc_8237E4A8;         // linha 422: volta ao topo
```

E a cadeia de chamadas:

| Onde | Função | O que faz com `r28` |
|---|---|---|
| `fc3_recomp.347.cpp:413` | `sub_8362B300` | thunk de tail-call, passa direto |
| `fc3_recomp.5.cpp:27289` | `sub_8362B300` -> `sub_8363CE50` | `b 0x8363ce50` (6 linhas, sem prólogo) |
| `fc3_recomp.325.cpp:28199` | `sub_8363CE50` | **`ld r28,264(r3)`** e `std r28,264(r5)` |
| `fc3_recomp.325.cpp` (fim) | `__imp__KeSetCurrentStackPointers` | tail-branch `b 0x83de04b4` |

`sub_8363CE50` **nao tem prologo**: nao ha `mflr r12`, nao ha `bl __savegprlr_N`, e termina em
`b 0x83de04b4` para `__imp__KeSetCurrentStackPointers`, sem `blr`. Os 778 passos intermediarios sao
uma copia de 128 registradores vetoriais (`lvxl128 v64`..`v127`) mais `mfcr r6` — o formato de uma
**rotina de troca de contexto do kernel**.

No Xbox 360 essa rotina **nao volta**: `KeSetCurrentStackPointers` troca os ponteiros de pilha do
kernel e o thread e despachado. Como o ReXGlue implementa a export como uma funcao C++ que
**retorna**, o fluxo volta para o loop de `sub_8237E408` — que nao estava preparado para isso — com
`r28` valendo `[r3+264]`, o campo do contexto de thread. Seis threads leem o mesmo campo nao
inicializado no mesmo instante: exatamente o que o log mostra.

## O defeito no SDK

`sdk/src/kernel/xboxkrnl/xboxkrnl_threading.cpp:270`

```cpp
void KeSetCurrentStackPointers_entry(mapped_void stack_ptr, ppc_ptr_t<X_KTHREAD> thread,
                                     mapped_void stack_alloc_base, mapped_void stack_base,
                                     mapped_void stack_limit) {
  auto current_thread = XThread::GetCurrentThread();
  auto context = current_thread->thread_state()->context();
  auto pcr = REX_KERNEL_MEMORY()->TranslateVirtual<X_KPCR*>(
      static_cast<uint32_t>(context->r13.u64));

  UpdateGuestStackPointers(thread, pcr, context, stack_ptr.guest_address(),
                           stack_alloc_base.value(), stack_base.value(), stack_limit.value());
}
```

Tres problemas, em ordem de gravidade:

1. **A export retorna.** No hardware ela nao retorna. O codegen do guest foi compilado assumindo
   que o caminho morre ali; com o stubvoltando, o guest continua num estado que so faz sentido
   depois de um despacho de thread.
2. **`GetCurrentThread()` pode ser nulo** e nao ha guarda nenhuma. A variante `NtSuspendThread`, na
   linha 230, trata `current_thread == nullptr` explicitamente — aqui nao.
3. **O argumento `thread` e ignorado** para localizar o PCR e o contexto: usa o `r13` da thread que
   esta rodando, em vez do `r13` da thread que esta sendo configurada. Durante uma troca de contexto
   sao threads diferentes.

## Como corrigir

Duas frentes, ambas ainda **nao testadas** (nao ha toolchain compilada neste ambiente):

**A. Fazer a export se comportar como no hardware.** Marcar `KeSetCurrentStackPointers` como
`noreturn` no grafo do codegen, para que o `b` do guest vire um tail-call de verdade e o fluxo nao
volte. Isso mexe em `sdk/src/codegen/phase_register.cpp` (onde `export_table.inc:169` declara a
export) e custa uma rodada de codegen de ~29 min.

**B. Blindar o stub.** Salvar e restaurar `r14`-`r31` e `r1` ao redor da chamada, e devolver
`thread` (e nao `current_thread`) para `UpdateGuestStackPointers`. E uma correcao local, sem codegen,
mas deixa o fluxo do guest semanticamente errado (ele continua num ponto em que, no hardware, estaria
suspenso).

**A e B sao complementares**: A corrige a raiz, B evita que o proximo stub com o mesmo formato volte a
derrubar o boot.

## Ferramenta

`tools/scan_savegpr.ps1` (criado nesta analise) procura funcoes do codegen que escrevem `r28`-`r31`
acima do que o helper `__savegprlr_N` do prologo declara.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\scan_savegpr.ps1
```

Ele acusa 44.348 funcoes, mas **e um falso positivo** (ver "Hipotese descartada"): `__savegprlr_N` nao
salva `r14..rN`, e sim `rN..r31`. Serve de rede de seguranca para quando o codegen voltar a rodar, nao
como diagnostico deste crash.

## Hipotese descartada: `sub_8362B1C0` e a ABI

O `RESUMO.md` apontava `sub_8362B1C0` (`fc3_recomp.110.cpp:26796`) por "fazer `mr r28,r4` e nunca
salvar `r28`", com `__savegprlr_27` no prologo. **Esta leitura estava errada.**

Os helpers do Xbox 360 nao salvam `r14..rN` como o nome sugere. `__savegprlr_27`
(`fc3_recomp.114.cpp:26756`) salva:

```cpp
// std r27,-48(r1)     -> __savegprlr_27 cobre r27..r31
// std r28,-40(r1)
// std r29,-32(r1)
// std r30,-24(r1)
// std r31,-16(r1)
// stw r12,-8(r1)
```

Ou seja, `_27` e o ponto de entrada da rotina que salva ate `r31`. `__savegprlr_31` existe e e
declarado (`0x8360DAE4`), mas nao e o unico caminho — os thunks de 4 bytes (`registerHelpers`, em
`phase_register.cpp:511`, com `stride = 4`) apontam todos para a mesma rotina maior.

Consequencia: **`sub_8237E408`, que usa `r28`-`r31` e chama `__savegprlr_27`, esta correto**, e o
`r28` do caller nao e destruido pelo prologo. Por isso o `r28` sobrevive as primeiras iteracoes e so
morre depois de `sub_8363CE50`.

## Como o diagnostico foi fechado (o symbolizer nao errava)

Uma nota anterior em `app/src/fc3_debug_hooks.cpp` dizia que o fault acontecia "varias chamadas mais
fundo" e que "o symbolizer esta errado, nao a traducao". **Isso estava errado.** Desmontando a
instrucao exata em `fc3.exe+0x79E9405` (RVA 0x79E9405, image base 0x140000000):

```
1479e93e7: movl  0xe0(%rdi), %eax        ; eax = ctx.<campo em 0xE0>
1479e93ed: movl  $0x13c, %ecx            ; 316
1479e93f2: addl  %ecx, %eax
1479e93f4: leaq  (%rsi,%rax), %rcx       ; base do convidado + isso
1479e93fa: cmpl  $0xe0000000, %eax
1479e9402: shll  $0xc, %edx             ; ajuste de pagina MMIO
1479e9405: movl  (%rdx,%rcx), %eax      ; <-- o fault
```

`PPCContext` (`sdk/include/rex/ppc/context.h:233`) tem `r3, r0, r1, r2, r4..r31` nessa ordem, com
8 bytes por registrador: **o offset 0xE0 e `r28`**. O bloco e exatamente a sequencia de carga de
convidado do ReXGlue para `lwz r11,316(r28)`. A traducao esta certa e `r28` vale 0.

Para fechar *"onde* o `r28` morre", dois hooks em `app/src/fc3_debug_hooks.cpp` medem `r28` em volta
de `sub_8362B300` e `sub_8363CE50` (`out/pc/logs/fc3_004.log`):

```
[dbg] IN  sub_8363CE50 #1 r28=83E1A148 r3=40007730 [r3+264]=00000000
[dbg] OUT sub_8363CE50 #1 r28=00000000  <<< DESTROYED
```

`sub_8363CE50` e a rotina de troca de contexto do kernel: `std r28,264(r5)` salva o `r28` do contexto
que sai no thread dono do PCR, e `ld r28,264(r3)` carrega o do contexto que entra. `r3 = 0x40007730` e
exatamente o contexto que `sub_8362B1C0` acabou de construir (o log mostra `OUT sub_8362B1C0 #1:
r3=40007730`), e `+264` nele e zero porque o thread ainda nao rodou — o que esta **correto**.

O que impede o zero de chegar ao caller e o fato de a export que encerra a rotina
(`KeSetCurrentStackPointers`) retornar. No console ela nao retorna: o thread e despachado.

## A correção

**Provisória, no app** (`app/src/fc3_debug_hooks.cpp`): o hook de `sub_8363CE50` salva e restaura
`r14`-`r31` em volta da chamada. O boot passou do fault e agora roda.

Tambem no SDK (`sdk/src/kernel/xboxkrnl/xboxkrnl_threading.cpp`): `KeSetCurrentStackPointers_entry`
agora tem guarda para `GetCurrentThread()` nulo (a versao anterior dereferenciava sem checar) e
documenta por que o retorno e um problema.

**A correcao de verdade** e no codegen: marcar a export como nao-retornante, para que o `b` do guest
vire um tail-call de verdade e o fluxo nao volte ao loop. Isso custa uma rodada de codegen de ~29 min
e ainda nao foi testado. Enquanto ela nao existir, o hook e o que mantem o boot andando.

O que o workaround **nao** resolve: ele devolve os registradores, mas nao faz o thread que foi
preparado rodar de verdade. O jogo segue criando threads que nunca executam. Se o boot travar adiante
num ponto que exija esses threads, o problema volta — e a hora de pagar a rodada de codegen.

## O que o boot alcança agora (fc3_006.log)

```
Function table initialized for module: code=82340000-83DF2AF4
SDL input driver initialized successfully
Initializing shader storage for title 5553088C...
[gpu] SetInterruptCallback(8365B5A0, 4003E980)        <- timer/interrupto montado
[error] [krnl] XamShowDirtyDiscErrorUI called!        <- e para aqui
```

O proximo bloqueio e `update:\patch.dat`, que o jogo le no comeco da inicializacao de conteudo. Ele
**existe** no console (particao de update) mas **nao esta no ISO extraido**: nenhum dos 17 `.fat` de
`assets/game_root` lista `patch.dat`, e a pasta `$SystemUpdate` do disco traz so os XEX do dashboard.

Montar o dispositivo resolve metade (`REX_update_data_root=<pasta>`, e o log passa a dizer
`mounted ... at \Device\Harddisk0\PartitionUpdate`), mas o jogo ainda chama
`XamShowDirtyDiscErrorUI`, porque o que ele quer e o arquivo. O proximo passo e descobrir o formato do
`patch.dat` e gerar um valido, ou convencer o jogo de que a ausencia e normal.