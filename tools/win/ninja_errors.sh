# Roda o ninja do build do mesa e mostra os erros, sem as linhas de comando gigantes.
# Sai em codigo diferente quando sobra trabalho: util para rodar depois de mexer em algo.
#
#   bash ninja_errors.sh [jobs]
export PATH="/usr/bin:/bin:$PATH"
BUILD=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx/out/mesa
JOBS=${1:-16}
cd "$BUILD" || exit 1
LOG=/tmp/ninja_errors.txt
ninja -k 0 -j "$JOBS" > "$LOG" 2>&1
code=$?
echo "== ninja exit: $code"
echo "== passos registrados: $(wc -l < "$BUILD/.ninja_log" 2>/dev/null || echo 0)"
echo "== erros"
tr -d '\r' < "$LOG" | grep -a -E 'FAILED|^error|error\[E|cannot find|not found|unresolved' | cut -c1-300 | sort -u | head -30
echo "== ultimas linhas do log"
tr -d '\r' < "$LOG" | grep -av '^\[' | tail -12 | cut -c1-300