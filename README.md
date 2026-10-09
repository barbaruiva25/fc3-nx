# fc3-nx

Port de **Far Cry 3** (Xbox 360, disco retail, title `5553088C`) para o **Nintendo Switch**, por recompilacao estatica
com [ReXGlue](https://github.com/rexglue/rexglue-sdk).

Derivado de [sa2-nx](https://github.com/ChanseyIsTheBest/sa2-nx) (Sonic Adventure 2 -> Switch): mesmo SDK, mesmas
ferramentas, mesmo renderer nativo. O que e especifico do FC3 e o manifest, as analises e o rendereradaptado.

Nao e emulacao. O codigo PowerPC do `default.xex` e convertido para C++ uma vez (ahead of time) e compilado para
o Switch; o desenho do jogo passa a ser feito por um renderer Vulkan nativo sobre o NVK (Mesa).

## Estado

Etapa 1 (recompilar e bootar no PC). O jogo esta extraido, o SDK configurado e o gerador de codigo compilando.
Veja `../docs/PLANO.md` para o andamento e `../docs/NOTAS-DE-BUILD.md` para as peculiarities do build.

## O jogo

| | |
|---|---|
| Fonte | `Far Cry 3 [MULTI][XBOX360][Region Free][XDG3].iso` (8,15 GB) |
| Title ID | `5553088C`, media `6F6EAD36`, versao `0.0.0.2` |
| `default.xex` | 11,5 MB (AES-128 + LZX), imagem descomprimida 33.947.648 bytes |
| Image base / entry | `0x82000000` / `0x82342D50` |
| Engine | Dunia 2 |

## O que e preciso

- **Sua propria copia do jogo.** Nenhum dado do jogo e distribuido aqui. O `default.xex` fica em
  `assets/game_root/` (junction para `../assets`, que e ignorado pelo git).
- **PC:** Windows 10/11, VS 2022 Build Tools, LLVM clang, Python 3, Git, devkitPro (devkitA64 + libnx).
- **Switch:** o NVK (Mesa para Switch) compilado como `libvulkan.a`, apontado por `NVK_SDK`.

## Build

```powershell
# 1. materializar o third-party do SDK (uma vez)
py -3 tools\fetch_thirdparty.py

# 2. compilar o gerador de codigo (uma vez)
powershell -NoProfile -ExecutionPolicy Bypass -File tools\win\run.ps1 out\host_configure.log `
  "cmake -S sdk -B out/host -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_FLAGS=-march=x86-64-v2 -DCMAKE_CXX_FLAGS=-march=x86-64-v2"
powershell -NoProfile -ExecutionPolicy Bypass -File tools\win\run.ps1 out\host_build.log "cmake --build out/host --target rexglue -j 24"

# 3. traduzir o jogo para C++ (escreve app/generated/)
powershell -NoProfile -ExecutionPolicy Bypass -File tools\codegen.ps1

# 4. build do PC
powershell -NoProfile -ExecutionPolicy Bypass -File tools\win\run.ps1 out\pc_configure.log "cmake --preset win-pc -S app"
powershell -NoProfile -ExecutionPolicy Bypass -File tools\win\run.ps1 out\pc_build.log "cmake --build out/pc -j 24"

# 5. rodar (mudo e minimizado por padrao)
powershell -NoProfile -ExecutionPolicy Bypass -File tools\win\boot_test.ps1
```

`-march=x86-64-v2` e obrigatorio no passo 2: o SDK usa intrinsecos SSSE3. Ver `../docs/NOTAS-DE-BUILD.md`.

## Estrutura

| Caminho | |
|---|---|
| `app/fc3_manifest.toml` | manifest do gerador: jogo, modulos, correcoes |
| `app/overrides.toml` | funcoes que a descoberta automatica nao alcanca (vazio por enquanto) |
| `app/src/me/` | renderer nativo (PM4 ring -> Vulkan), vindo do sa2-nx |
| `app/src/cpu/` | otimizacoes de CPU e funcoes nativas |
| `sdk/` | fork do ReXGlue com a camada Horizon (Switch) |
| `shaders/XenosRecomp/` | tradutor de microcode Xenos -> HLSL |
| `tools/` | ferramentas de analise e build do sa2-nx |
| `docs/` | o guia de porting e os planos deste port |

## Licenca

GPL-3.0, como o sa2-nx e o ReXGlue. Nenhum dado do jogo aqui.