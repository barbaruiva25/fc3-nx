# 01 — O projeto

**Far Cry 3 (Xbox 360, disco retail, title `5553088C`) -> Nintendo Switch**, por recompilacao estatica
com [ReXGlue](https://github.com/rexglue/rexglue-sdk). Nao e emulacao: o PowerPC do `default.xex` vira
C++ uma vez (ahead of time) e compila para o Switch; o desenho passa a ser feito por um renderer
Vulkan nativo sobre o NVK (Mesa).

## Raizes

- Codigo: `C:\Users\barba\Documents\xbox360\FARCRY3\xbox360\fc3-nx\`
- Mesa (driver NVK): `C:\Users\barba\Documents\xbox360\FARCRY3\xbox360\mesa-switch\` (commit `1a8c1a66d6f`)
- Dados do jogo: `C:\Users\barba\Documents\xbox360\FARCRY3\xbox360\assets\game_root\` (5,77 GB, 109 entradas)
- `fc3-nx\assets` e um **junction** para `..\assets` (nao um diretorio de verdade)

## O jogo

| | |
|---|---|
| Fonte | `Far Cry 3 [MULTI][XBOX360][Region Free][XDG3].iso` (8,15 GB) |
| Title ID / Media ID | `5553088C` / `6F6EAD36`, versao `0.0.0.2` |
| `default.xex` | 12.042.240 bytes, imagem 33.947.648 bytes, base `0x82000000`, entry `0x82342D50` |
| Engine | Dunia 2 |
| Codegen | 883 funcoes, 440 `.cpp`, ~450 MB em `app/generated/default/` |

## As 4 etapas

1. Recompilar e bootar no **PC** (`fc3.exe`) — em andamento, crash resolvido, trava em dado faltante
2. Renderer nativo Vulkan — **nao comecada** (`app/src/me/` ainda tem enderecos de Direct3D do Sonic Adventure 2)
3. NRO para o **Switch** — CMake/toolchain/scripts prontos, **nunca compilado**; depende do `libvulkan.a`
4. Desempenho — nao comecada

## Caminhos de saida (quando existirem)

| Artefato | Caminho |
|---|---|
| NRO | `fc3-nx/out/nx/fc3.nro` |
| Pacote SD | `fc3-nx/out/nx/sdcard/switch/fc3-nx/` (copiar para `sdmc:/switch/` no cartao) |
| PC | `fc3-nx/out/pc/fc3.exe` |
| Logs de boot | `fc3-nx/out/pc/logs/fc3_NNN.log` |
| Driver Vulkan | `fc3-nx/mesa-switch-install/opt/devkitpro/portlibs/switch/lib/libvulkan.a` |