# Testa wpath() do wrapper do bindgen isolado.
export PATH="/usr/bin:/bin:$PATH"
wpath() {
    case "$1" in
        -I/*|-idirafter/*|-iprefix/*|-iwithprefix/*|-iwithprefixbefore/*)
            flag="${1%%/*}"; p="/${1#*/}"; p="${p%/}"
            echo "${flag}$(cygpath -w "$p")" ;;
        -isystem/*|-imsvc/*)
            flag="${1%%/*}"; p="/${1#*/}"; p="${p%/}"
            echo "${flag}$(cygpath -w "$p")" ;;
        /*) p="${1%/}"; cygpath -w "$p" ;;
        *)  printf '%s' "$1" ;;
    esac
}
echo "in : -I/c/Users/barba/x/include/"
echo -n "out: "; wpath '-I/c/Users/barba/x/include/'; echo
echo -n "out: "; wpath '/opt/devkitpro/lib/'; echo
echo -n "out: "; wpath '-DXXH_FORCE_ALIGN_CHECK=0'; echo