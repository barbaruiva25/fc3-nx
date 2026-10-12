# Extrai o comando do ninja para nak_bindings.rs, roda pelo wrapper com dump dos args e mostra
# so o lado do clang (apos o --). O panic do bindgen nao mostra o diagnostico real.
export PATH="/usr/bin:/bin:$PATH"
export MESA_SWITCH_BINDGEN=/c/Users/barba/.cargo/bin/bindgen.exe
export DEVKITPRO=/opt/devkitpro
export MESA_SWITCH_DEBUG_ARGS=/tmp/nak.txt
cd /c/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx/out/mesa || exit 1
CMD=$(sed -n '5526p' build.ninja | sed 's/^ *COMMAND = //')
eval "$CMD" > /tmp/nak_out.txt 2>&1
echo "bindgen exit=$?"
echo "== clang args (apos --) =="
awk '/^--$/{f=1; next} f' /tmp/nak.txt
echo "== saida (10 primeiras) =="
head -10 /tmp/nak_out.txt