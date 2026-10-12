# Roda o ninja do build do mesa direto, para ver o erro que o build_nvk.ps1 nao registra.
#   bash ninja_mesa.sh [jobs] [-k 0]
#
# O log do build_nvk.ps1 termina em "ninja: build stopped" sem a mensagem: o ninja escreve o erro em
# stderr com sequencias de cores e \r, que a redirecao do PowerShell come. Aqui a saida vai crua.
set -o pipefail
export PATH="/usr/bin:/bin:$PATH"
BUILD=${2:-/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx/out/mesa}
JOBS=${1:-16}
KEEP=${3:-}
cd "$BUILD" || exit 1
# As linhas de comando do ninja sao de milhares de caracteres e escondem o erro. Fica so o que o
# compilador falou, mais a linha "FAILED:" que diz qual arquivo.
ninja -C "$BUILD" -j "$JOBS" $KEEP 2>&1 \
    | grep -av '^\[' \
    | grep -a -B1 -E 'error:|Error [0-9]|undefined reference|No such file|cannot find|collect2' \
    | cut -c1-400 \
    | tail -40
echo "== ninja exit: ${PIPESTATUS[0]}"