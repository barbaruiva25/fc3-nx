# Acha o pacote que entrega libzstd para Switch.
export PATH="/usr/bin:/bin:$PATH"
echo "== todos os pacotes switch com zstd no nome =="
pacman -Ss zstd 2>&1 | grep -B1 -i switch | head -12
echo
echo "== dono de algum zstd? =="
pacman -Fy 2>&1 | tail -1
pacman -Fo /opt/devkitpro/portlibs/switch/lib/libzstd.a 2>&1 | head -4