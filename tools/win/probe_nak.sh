# Roda o comando EXATO do ninja para nak_bindings.rs, para ver o erro real do bindgen/libclang.
# O log do ninja so mostra "panicked ... libclang error" sem o diagnostico do clang.
export PATH="/usr/bin:/bin:$PATH"
export MESA_SWITCH_BINDGEN=/c/Users/barba/.cargo/bin/bindgen.exe
export DEVKITPRO=/opt/devkitpro
cd /c/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx/out/mesa || exit 1
CMD=$(sed -n '5526p' build.ninja | sed 's/^ *COMMAND = //')
eval "$CMD" 2>&1 | head -40
echo "exit=$?"