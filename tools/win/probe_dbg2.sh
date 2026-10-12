# Testa o wrapper REAL com os args crus exatos do ninja.
export PATH="/usr/bin:/bin:$PATH"
export MESA_SWITCH_BINDGEN=/c/Users/barba/.cargo/bin/bindgen.exe
export DEVKITPRO=/opt/devkitpro
export MESA_SWITCH_DEBUG_ARGS=/tmp/dbg2.txt
W=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx/tools/win/bindgen-switch-fc3.sh
echo 'int x;' > /tmp/fake.h
"$W" /tmp/fake.h --output /tmp/fake.rs -- \
  '-I/C/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx/out/mesa/src/.' \
  '-I/C/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx/out/mesa/src/compiler/.' \
  -DXX=0 2>&1 | head -3
echo "== dump (lado clang) =="
awk '/^--$/{f=1; next} f' /tmp/dbg2.txt