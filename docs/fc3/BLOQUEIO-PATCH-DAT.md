# Bloqueio: o Title Update (`UPDATE:\patch.dat` + `patch.fat`)

Data: 2026-10-10. Desbloqueia a Etapa 1, que parou aqui depois de resolvido o crash `0x13C`.

## O sintoma

Com o jogo bootando pela primeira vez, o log (`out/pc/logs/fc3_007.log`) mostra:

```
[warning] [krnl] [NtCreateFile] FAILED: path='UPDATE:\patch.fat' -> 0xc000000f
[error]   [krnl] XamShowDirtyDiscErrorUI called! user_index=0
```

O jogo vai ate `XamShowDirtyDiscErrorUI` — a tela de "disco sujo / desatualizado" — e para ali. Nao e
crash: e uma saida controlada do codigo do jogo, e o emulador so registra a chamada
(`sdk/src/kernel/xam/xam_ui.cpp:519`).

## O que ele quer

**Um par de containeres `.dat` + `.fat` em `UPDATE:\`.** O `.fat` e o indice de diretorio (nomes e
tamanhos) e o `.dat` os dados — exatamente o mesmo par que o proprio disco do jogo usa em
`assets/game_root`: `common.dat`/`common.fat`, `ige.dat`/`ige.fat`, `sound.dat`/`sound.fat`,
`startup.dat`/`startup.fat`, `shadersobj.dat`/`shadersobj.fat`.

Ou seja: o jogo esta pedindo o **Title Update (TU)** do Far Cry 360 empacotado como container de disco.
Nao e um arquivo de configuracao e nao da para fabricar com um stub.

## Por que ele nao esta no ISO

`UPDATE:` no Xbox 360 nao aponta para o disco. Aponta para a particao do **HD do console**, onde o
dashboard baixa os TUs. O disco do Far Cry 3 (title `5553088C`, versao `0.0.0.2`) e o disco base e nao
traz o container:

- nenhum dos 17 arquivos `.fat` de `assets/game_root` lista `patch.dat`;
- a pasta `$SystemUpdate/` do disco traz so os XEX do dashboard e `system.manifest` — e update de
  **sistema**, nao de titulo.

E um caso conhecido: a documentacao da comunidade de emulacao lista varios jogos Xbox 360 que
**exigem um ou mais Title Updates para bootar**, e o Far Cry 360 esta entre eles (title
`5553088C`, publicado em 2012, com TUs publicados pela Microsoft).

## Confirmacoes que ja feitas

1. Sem `update:` montado: `ResolvePath(update:\patch.dat) failed - device not found`.
2. Com `REX_update_data_root=<pasta>`: o dispositivo monta
   (`mounted ... at \Device\Harddisk0\PartitionUpdate`) e o jogo passa a tentar abrir `patch.fat`.
3. Com um `patch.dat` **vazio** criado a mao: o jogo ainda pede `patch.fat` e ainda chama
   `XamShowDirtyDiscErrorUI`. Um stub nao resolve — ele quer o conteudo.

## O que precisa

**O Title Update do Far Cry 360**, no formato que o console instalaria, com o par `patch.dat` +
`patch.fat`. Onde costuma estar:

- a colecao `microsoft_xbox360_title-updates` do [archive.org](https://archive.org/details/microsoft_xbox360_title-updates)
  (a Microsoft distribuia TUs de graça; o archive.org os preserva)
- o dump/backup do HD de um console que tenha rodado o jogo

O `.xexp` do TU e um pacote STFS; o par `patch.dat`/`patch.fat` e a forma como o console o deixa no
disco depois de instalado. O `tools/stfs_extract.py` do projeto pode extrair o `.xexp`.

## Onde o TU foi localizado (2026-10-11)

A colecao `microsoft_xbox360_title-updates` do archive.org tem o arquivo exato:

```
Far Cry 3 (World) (v5) (6F6EAD36) (Title Update).zip   7,48 MB
```

**O Media ID `6F6EAD36` bate com o do `default.xex` deste projeto** (`Media ID: 6F6EAD36` no log do
codegen), entao e o TU certo. A v5 e a ultima.

**Mas o download direto responde `403 Forbidden`.** O item tem `access-restricted-item: true` na
colecao: precisa de uma conta no archive.org e de um emprestimo manual do arquivo. Nao contornei isso.

### Como obter

1. **Emprestar no archive.org** (conta gratuita): abrir
   <https://archive.org/details/microsoft_xbox360_title-updates>, fazer login, abrir o arquivo e pedir o
   emprestimo. O `.zip` tem 7,48 MB.
2. **Do proprio console**: o `patch.dat`/`patch.fat` e como o TU fica no disco depois de instalado. Um
   dump de `Content\5553088C\` de um console que rodou o jogo ja serve, sem passar pelo `.xexp`.
3. **Pular esta etapa**: o NRO compila e roda no Switch mesmo assim (ver "Enquanto isso" abaixo).

### Convertendo para `UPDATE:\`

O `.zip` traz o TU no formato `.xexp` (pacote STFS). O jogo quer o par `patch.dat` + `patch.fat`, que e
a forma que o console deixa no disco. `tools\stfs_extract.py` extrai o `.xexp`; da para usar o mesmo
montador de `.dat`/`.fat` que o SDK usa para os containers do proprio jogo (eles estao em
`assets/game_root`: `common.dat`/`common.fat` etc.) e escrever o TU com o mesmo formato.

Isso ainda nao foi implementado — e o passo a fazer quando o arquivo estiver na mao.

## Enquanto isso

Isso **nao** bloqueia a Etapa 3. O NRO pode ser compilado e testado no console mesmo com o jogo
parando nesta tela: o que a Etapa 3 precisa e que o build exista e a imagem de driver (`libvulkan.a`
do NVK) linke. Ver `NOTAS-DE-BUILD.md` §10 e o build em `tools/win/build_nvk.ps1`.

O caminho para o console e, em ordem:

1. `libvulkan.a` do NVK (build longo, em andamento)
2. `tools\win\build_switch.ps1` -> `out\nx\fc3.nro`
3. `tools\win\package_switch.ps1` -> `out\nx\sdcard\switch\fc3-nx\`
4. copiar `fc3-nx\` para `sdmc:/switch/` no cartao