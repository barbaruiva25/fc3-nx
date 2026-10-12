# 04 — Diagnosticos do boot

## 4.1 Crash `0x13C` — RESOLVIDO em 2026-10-10

Sintoma (6 threads, mesmo instante, mesmo PC):

```
[error] Unhandled guest access violation: read of guest 0x0000013C (fc3.exe+0x79E9405)
```

Cadeia comprovada, com numeros de linha:

- `0x13C = 316` = displacement de `lwz r11,316(r28)` (`app/generated/default/fc3_recomp.347.cpp:319`).
  Logo `r28 = 0`. Instrucao confirmada desmontando `fc3.exe+0x79E9405` (RVA): a sequencia e
  `movl 0xe0(%rdi),%eax; movl $0x13c,%ecx; ...; movl (%rdx,%rcx),%eax`, e `0xE0` de `PPCContext`
  (`sdk/include/rex/ppc/context.h:233`) e exatamente `r28`.
- `sub_8363CE50` (`fc3_recomp.325.cpp:28199`, rotina de troca de contexto do kernel, sem prologo) faz
  `ld r28,264(r3)`. O contexto (`r3 = 0x40007730`, recem-construido) tem `+264 = 0` — correto, a thread
  nunca rodou. Medido por hook: `IN r28=83E1A148 [r3+264]=00000000` / `OUT r28=00000000`.
- No console isso e seguro porque `KeSetCurrentStackPointers` **nao retorna** (o thread e despachado).
  No ReXGlue ela retorna (`sdk/src/kernel/xboxkrnl/xboxkrnl_threading.cpp:270`), e o caller volta ao
  loop com `r28 = 0`.

Correcao aplicada (provisoria, no app): hook de `sub_8363CE50` em `app/src/fc3_debug_hooks.cpp` salva e
restaura `r14`-`r31` em volta da chamada. Tambem ha guarda de `GetCurrentThread()` nulo no SDK.

Correcao definitiva (nao feita): marcar a export como nao-retornante no codegen (~29 min de codegen).
Aviso: o workaround devolve registradores mas nao faz o thread preparado rodar; se o boot travar num
ponto que exija esses threads, pagar a rodada de codegen.

Duas leituras anteriores, ambas refutadas com evidencia e registradas, para nao reabrir:
`sub_8362B1C0` violando ABI (falso: `__savegprlr_27` salva `r27..r31`) e "o symbolizer erra" (falso:
desmontagem confirma `ctx.r28 + 316`).

Documento completo: `docs/fc3/DIAGNOSTICO-BOOT-0x13C.md`.

## 4.2 `update:\patch.dat` — BLOQUEIO ATUAL (dados)

O jogo abre `UPDATE:\patch.fat` (-> `0xc000000f`) e chama `XamShowDirtyDiscErrorUI`. Depois disso nao
faz mais nenhuma I/O: e fatal. Nao e stubavel (testado: `patch.dat` vazio nao adianta; ele quer o
conteudo). Ver `02-estado.md` item A e `docs/fc3/BLOQUEIO-PATCH-DAT.md`.

Montar o dispositivo: `REX_update_data_root=<pasta>` (o log diz
`mounted ... at \Device\Harddisk0\PartitionUpdate`). A pasta `assets\update` existe para isso.