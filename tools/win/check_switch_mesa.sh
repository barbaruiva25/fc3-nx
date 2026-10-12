# O switch-mesa do devkitPro traz o NVK pronto: libvulkan.a para o Switch, sem cross build.
# Os ports da comunidade (defjam-sw, nfsu2-sw) usam este pacote em vez de compilar o Mesa a mao.
export PATH="/usr/bin:/bin:$PATH"
pacman -Ss mesa 2>&1 | grep -iE "switch-mesa|mesa" | head -20
echo "== procurar switch-mesa =="
pacman -Si switch-mesa 2>&1 | head -12