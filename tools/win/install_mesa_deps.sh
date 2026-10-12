# Pacotes que o cross build do mesa-switch precisa no MSYS2. Rodar uma vez.
#
# por que pacman e nao pip: o Python do MSYS2 e PEP 668 (externamente gerenciado) e o pip recusa
# instalar nele. E por que este script existe: chamado de um shell do Windows, o PATH nao traz
# /usr/bin, entao o primeiro pacman falha com "command not found".
#
#   bash install_mesa_deps.sh
set -e
export PATH="/usr/bin:/bin:$PATH"

pacman -S --needed --noconfirm \
    python python-pip meson ninja make \
    python-setuptools python-mako python-markupsafe python-yaml \
    bison flex pkgconf git

# byacc is not a package in any current MSYS2 repo, and mesa-build does not need it: meson.build:2240
# looks for bison first and only reaches byacc at 2243 when bison is missing. So bison is the fix.

echo '== check'
for t in python meson ninja make bison flex pkgconf git; do
    printf '%-10s %s\n' "$t" "$(command -v "$t" || echo AUSENTE)"
done
/usr/bin/python -c 'import mesonbuild, setuptools, mako, markupsafe, yaml; print("python deps OK")'
/usr/bin/python -m mesonbuild.mesonmain --version