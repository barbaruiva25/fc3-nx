# Verifica se o pacote switch-zstd existe no devkitPro e instala.
export PATH="/usr/bin:/bin:$PATH"
echo "== procura zstd =="
pacman -Ss zstd 2>&1 | grep -i switch | head -5
echo "== instala =="
pacman -S --needed --noconfirm switch-zstd 2>&1 | tail -4
echo "== confere =="
ls /opt/devkitpro/portlibs/switch/lib/ | head -20