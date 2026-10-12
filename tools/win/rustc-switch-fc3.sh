#!/bin/bash
# Wrapper de rustc para o cross build do mesa-switch (Switch / aarch64).
#
# Por que este wrapper existe
# --------------------------
# O meson precisa de um binario 'rust' em [binaries] para o NAK (o compilador de shaders do NVK), e o
# rustc-switch-wrapper.sh da arvore nao serve nesta maquina:
#
#   1. No probe de sanidade, ele troca o linker por um gcc MINGW64. O rustup por omrao e
#      x86_64-pc-windows-**msvc**, e esse rustc passa argumentos MSVC (/NOLOGO, kernel32.lib) para um
#      gcc que nao entende. Trocar o toolchain padrao para stable-x86_64-pc-windows-gnu resolve, mas
#      ainda sobra `collect2: ld returned 53` — o ld que o collect2 acha nao linka esses objetos.
#
#   2. A correcao mais simples e deixar o probe usar o linker PADRAO do proprio rustc, que funciona
#      (ele linka o probe em Windows sem espaco para problema nenhum). O probe so precisa de um binario
#      que rode no host; nao compila nada do alvo.
#
# No build de verdade o que importa e o --target: o NAK e compilado para aarch64 e linkado pelo
# aarch64-none-elf-gcc que o meson passa.
set -e

RUSTC="${MESA_SWITCH_RUSTC:-}"
if [ -z "$RUSTC" ]; then
    for candidate in \
        /c/Users/barba/.cargo/bin/rustc.exe \
        /usr/bin/rustc \
        "$(command -v rustc || true)"
    do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then RUSTC="$candidate"; break; fi
    done
fi
: "${RUSTC:?rustc nao encontrado: defina MESA_SWITCH_RUSTC}"

TARGET="${MESA_SWITCH_RUST_TARGET:-aarch64-unknown-linux-gnu}"

# O probe do meson tem nome proprio. Nesse caso: sem --target (para nao pedir std aarch64) e sem
# -C linker (para o rustc usar o seu), que e o que de fato funciona nesta maquina.
is_probe=0
for arg in "$@"; do
    case "$arg" in
        *sanity_check_for_rust.rs*|*sanitycheckrs.rs*) is_probe=1 ;;
    esac
done

if [ "$is_probe" = "1" ]; then
    args=(); skip_next=0
    for arg in "$@"; do
        if [ "$skip_next" = "1" ]; then
            skip_next=0
            case "$arg" in linker=*) continue ;; esac
            args+=("$arg"); continue
        fi
        case "$arg" in
            -Clinker=*) continue ;;
            -C) skip_next=1 ;;
            *) args+=("$arg") ;;
        esac
    done
    exec "$RUSTC" "${args[@]}"
fi

exec "$RUSTC" --target="$TARGET" "$@"