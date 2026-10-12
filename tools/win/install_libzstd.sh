# Instala libzstd para Switch (o link do NRO pede -lzstd).
export PATH="/usr/bin:/bin:$PATH"
pacman -S --needed --noconfirm switch-libzstd
echo "== confere =="
ls /opt/devkitpro/portlibs/switch/lib/ | grep -i zstd