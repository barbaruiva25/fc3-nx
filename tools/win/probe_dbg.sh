# Chama o wrapper REAL do bindgen com um -I com barra final, e mostra o que sai no dump.
export PATH="/usr/bin:/bin:$PATH"
export MESA_SWITCH_BINDGEN=/c/Users/barba/.cargo/bin/bindgen.exe
export DEVKITPRO=/opt/devkitpro
export MESA_SWITCH_DEBUG_ARGS=/tmp/dbg1.txt
W=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx/tools/win/bindgen-switch-fc3.sh
echo "== wrapper mtime =="
ls -l "$W"
echo "== chamada =="
"$W" --version 2>&1 | head -2
echo "== teste wpath via chamada real com header fake =="
echo 'int x;' > /tmp/fake.h
"$W" /tmp/fake.h --output /tmp/fake.rs -- -I/c/Users/barba/x/include/ -DXX=0 2>&1 | head -3
echo "== dump =="
cat /tmp/dbg1.txt