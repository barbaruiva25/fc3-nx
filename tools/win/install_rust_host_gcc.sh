# Pacotes do MSYS2 que o wrapper do rustc do mesa precisa.
#
# rustc-switch-wrapper.sh faz o probe de sanidade do meson linkando com um compilador NATIVE (o probe
# so precisa de um binario que rode no host); sem nenhum gcc MINGW64 ele cai no "linker not found".
export PATH="/usr/bin:/bin:$PATH"
pacman -S --needed --noconfirm mingw-w64-x86_64-gcc
echo "== check"
ls -l /mingw64/bin/gcc.exe 2>&1
/mingw64/bin/gcc.exe --version 2>&1 | head -1