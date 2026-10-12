# Instala o switch-mesa do devkitPro: Mesa com o driver nouveau pronto para o Switch, em vez de
# compilar o Mesa a mao. E o que os ports da comunidade usam (defjam-sw, nfsu2-sw citam
# "devkitPro's switch-mesa").
export PATH="/usr/bin:/bin:$PATH"
pacman -S --needed --noconfirm switch-mesa

echo
echo "== o que veio =="
ls -la /opt/devkitpro/portlibs/switch/lib/ 2>&1 | head -30
echo
echo "== libvulkan? =="
find /opt/devkitpro/portlibs/switch -name 'libvulkan*' -o -name 'libnvk*' 2>/dev/null
echo
echo "== headers? =="
ls /opt/devkitpro/portlibs/switch/include 2>&1 | head -20