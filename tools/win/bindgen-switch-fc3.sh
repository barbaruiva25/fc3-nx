#!/bin/bash
# bindgen para o cross build do mesa-switch (Switch / aarch64), numa versao que funciona nesta maquina.
#
# Uso:  bindgen [opcoes] headers... -- [args do clang]
#
# Faz duas coisas que o bindgen-switch-wrapper.sh da arvore fazia, e corrige tres problemas dele:
#
# 1. --no-layout-tests e --opaque-type __sFILE. O FILE do devkitA64 falha no teste de tamanho que o
#    bindgen gera (184 calculado, 176 emitido), e o Mesa so o usa por ponteiro.
#
# 2. Injeta o shim de tipos atomicos C11 depois do "--", para o clang. O wrapper da arvore passa o
#    caminho MSYS2 (/c/Users/.../bindgen-atomic-shim.h) e o clang, que e binario NATIVO do Windows,
#    responde "fatal error: ... file not found" com o arquivo ali do lado. Aqui o caminho passa por
#    cygpath -w antes, que e o que o clang entende. O mesmo vale para todos os -I que o meson passa
#    em formato MSYS2 - e para o trailing "/." deles (vira backslash no fim, que escapa o argumento
#    seguinte e da o panic opaco "libclang error ... Invalid flag syntax").
#
# 3. Remove flags do DRIVER gcc que o meson repassa e o libclang nao reconhece (-pthread, -MD, -MQ,
#    -MF, -MT, -MP, -MG): cada uma vira o panic opaco "libclang error ... Unrecognized flags".
#
# 4. --target=aarch64-none-elf, como o wrapper da arvore: sem ele o libclang cai nos headers do MSVC
#    do host ("conflicting types for '_InterlockedDecrement64'" em intrin0.inl.h).
#
# Tudo com ARRAYS, nao com strings: valores com espaco (p.ex. --raw-line 'pub use x::y;') sao
# destruidos por concatenacao em string plana + expansao sem aspas, e viram "headers" fantasmas.
# Sem o "--" nos argumentos (chamada so de --version, ou o probe do meson), nada e injetado.
set -e

MESA=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/mesa-switch
BINDGEN="${MESA_SWITCH_BINDGEN:-}"
if [ -z "$BINDGEN" ]; then
    for c in /c/Users/barba/.cargo/bin/bindgen.exe /usr/bin/bindgen; do
        [ -x "$c" ] && { BINDGEN="$c"; break; }
    done
fi
[ -n "$BINDGEN" ] || BINDGEN="$(command -v bindgen || true)"
: "${BINDGEN:?bindgen nao encontrado: defina MESA_SWITCH_BINDGEN}"

case "$*" in
    *--version*) exec "$BINDGEN" "$@" ;;
esac

DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
SHIM=$(cygpath -w "$MESA/bindgen-atomic-shim.h")
SYSINC=$(cygpath -w "$DEVKITPRO/devkitA64/aarch64-none-elf/include")
LIBNXINC=$(cygpath -w "$DEVKITPRO/libnx/include")

stripSlash() { _p="$1"; _p="${_p%/.}"; _p="${_p%/}"; printf '%s' "$_p"; }
wpath() {
    case "$1" in
        -I/*|-idirafter/*|-iprefix/*|-iwithprefix/*|-iwithprefixbefore/*)
            flag="${1%%/*}"; printf '%s' "${flag}$(cygpath -w "$(stripSlash "/${1#*/}")")" ;;
        -isystem/*|-imsvc/*)
            flag="${1%%/*}"; printf '%s' "${flag}$(cygpath -w "$(stripSlash "/${1#*/}")")" ;;
        /*) cygpath -w "$(stripSlash "$1")" ;;
        *)  printf '%s' "$1" ;;
    esac
}

before=()
after=()
seen=0
skip=0
for a in "$@"; do
    if [ "$skip" = "1" ]; then skip=0; continue; fi
    if [ "$a" = "--" ]; then seen=1; continue; fi
    if [ "$seen" = "0" ]; then before+=("$a"); continue; fi
    case "$a" in
        -pthread|-MD|-MP|-MG) continue ;;
        -MQ|-MF|-MT) skip=1; continue ;;
        -MQ*|-MF*|-MT*) continue ;;
        *) after+=("$(wpath "$a")") ;;
    esac
done

if [ "$seen" = "0" ]; then
    exec "$BINDGEN" --no-layout-tests --opaque-type __sFILE "$@"
fi

CLANG_RES=""
CLANG_BIN="${MESA_SWITCH_CLANG:-$(command -v clang || true)}"
if [ -n "$CLANG_BIN" ]; then
    CLANG_RES=$(cygpath -w "$("$CLANG_BIN" -print-resource-dir)/include" 2>/dev/null || echo "")
fi

isystems=()
[ -n "$CLANG_RES" ] && isystems+=(-isystem "$CLANG_RES")
isystems+=(-isystem "$SYSINC" -isystem "$LIBNXINC")

if [ -n "${MESA_SWITCH_DEBUG_ARGS:-}" ]; then
    { echo "--- bindgen argv ---"
      printf '%s\n' --no-layout-tests --opaque-type __sFILE "${before[@]}" --
      printf '%s\n' --target=aarch64-none-elf -include "$SHIM" "${isystems[@]}" "${after[@]}"
    } > "$MESA_SWITCH_DEBUG_ARGS"
fi

exec "$BINDGEN" --no-layout-tests --opaque-type __sFILE "${before[@]}" -- \
    --target=aarch64-none-elf \
    -include "$SHIM" \
    "${isystems[@]}" \
    "${after[@]}"