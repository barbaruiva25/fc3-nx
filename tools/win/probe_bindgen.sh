# Roda o bindgen no header do NAK a mao, com os mesmos argumentos do meson, para ver o erro do
# libclang com detalhe. O log do ninja so diz "panicked ... libclang error".
export PATH="/usr/bin:/bin:$PATH"
export MESA_SWITCH_BINDGEN=/c/Users/barba/.cargo/bin/bindgen.exe
export DEVKITPRO=/opt/devkitpro
MESA=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/mesa-switch
W="$MESA/../fc3-nx/tools/win/bindgen-switch-fc3.sh"

cd /c/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx/out/mesa || exit 1

echo "== tentativa simplificada (sem os -I do ninja) =="
"$W" "$MESA/src/nouveau/compiler/nak_bindings.h" --output /tmp/nak_test.rs -- \
    -I"$MESA/src" -I"$MESA/src/gallium" -I"$MESA/src/gallium/include" -I"$MESA/include" 2>&1 | head -30
echo "exit=$?"
ls -la /tmp/nak_test.rs 2>&1 | head -1