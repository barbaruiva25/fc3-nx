# 03 — Ambiente (tudo instalado em 2026-10-10/11, nada existia antes)

| Ferramenta | Onde | Versao |
|---|---|---|
| VS 2022 Build Tools (C++ x64) | `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools` | com CMake 3.31.6 + Ninja 1.12.1 |
| LLVM/clang | `C:\Program Files\LLVM` | 23.1.3 |
| Python | `%LOCALAPPDATA%\Programs\Python\Python313` | 3.13.15 |
| git | `C:\Program Files\Git` | winget |
| devkitA64 + libnx | `C:\devkitPro` (junction -> `C:\msys64\opt\devkitpro`) | GCC 16.1.0, libnx 4.12.0 |
| MSYS2 | `C:\msys64` | base via `msys2-base-*.tar.xz` do GitHub |
| rustup | `%USERPROFILE%\.cargo` | toolchain padrao `stable-x86_64-pc-windows-gnu` + target `aarch64-unknown-linux-gnu` + `rustfmt` |
| bindgen-cli | `%USERPROFILE%\.cargo\bin\bindgen.exe` | 0.73.2 (cbindgen NAO serve; o Mesa exige >= 0.71.1) |

Pacotes MSYS2 instalados para o Mesa: `python meson ninja make bison flex pkgconf git
python-setuptools python-mako python-markupsafe python-yaml mingw-w64-x86_64-gcc`.
Script: `tools/win/install_mesa_deps.sh` (+ `install_rust_host_gcc.sh`).

## Peculiaridades (cada uma custou tempo; respeite)

1. **MSYS2 do winget falha** (`0xC0000135`). Usar o `msys2-base.tar.xz` do GitHub, extrair em `C:\`.
2. **gpg do MSYS2 nao alcanca keyserver.** Baixar as chaves devkitPro pelo PowerShell
   (`BC26F752...`, `62C7609A...`) e `pacman-key --add` em `C:\msys64\home\<usuario>\`.
3. **Repositorio `[dkp-windows]` usa `x86_64` literal**, nao `$arch` (o PowerShell expande antes do bash).
4. **`C:\devkitPro` precisa ser junction** para `C:\msys64\opt\devkitpro` (layout atual do instalador).
5. **Todo build passa por `tools/win/run.ps1`** (carrega `env.ps1`: MSVC + clang + CMake + Ninja + Python).
   `env.ps1` poem o Python real no PATH (o alias da Store abre a loja em vez de rodar).
6. **Build do PC para depois do codegen**: `cmake --build` roda o passo de codegen e sai com exit 0
   **sem compilar**. Rodar o configure depois (`cmake --preset win-pc -S app`) e buildar de novo.
   Sempre conferir o timestamp de `out/pc/fc3.exe`.
7. **Shell do Windows nao tem `git`/etc no PATH de sessoes antigas.** Recarregar o PATH da maquina+
   usuario no inicio de cada sesso de instalacao.