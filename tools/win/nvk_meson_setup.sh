#!/bin/bash
# Full cross build of mesa-switch -> a static libvulkan.a for the Switch NRO.
#
# Run by tools/win/build_nvk.ps1. Which commit matters: the NVK driver and the Horizon backend are NOT on this
# fork's `main` any more. They exist at the commit the other Switch ports build from:
#
#     git checkout 1a8c1a66d6fd8d65f10107c4627ffc3606ba5631   (Mesa 26.2.x, nvkmd/switch + nouveau/horizon)
#
# The nfsmw-nx patch (mesa/mesa-switch-nfsmw.patch) then applies on top and gives the driver changes the released
# NROs have (ZCULL, cheaper draws, set 4 by differences, uncached memory, the NAK scheduling fixes). Without it the
# driver still builds and runs, just slower and with the "black sea" bug.
#
#   bash nvk_meson_setup.sh <source> <builddir> <install-prefix> <host-python>
#
# ALL FOUR ARGUMENTS ARE MSYS2 PATHS. The cross file names its compilers as /opt/devkitpro/..., so meson has to run as
# MSYS2's Python: with the Windows Python the paths do not resolve and the first error is a misleading
# "prefix ... must be an absolute path".
#
# The consequence is that the Ninja steps run MSYS2's Python too, which is missing setuptools/mako/markupsafe. Those are
# installed into MSYS2's site-packages by tools/win/install_meson_msys2.sh's siblings (see docs/NOTAS-DE-BUILD.md).
set -e

SRC="$1"
BUILD="$2"
PREFIX="$3"
EXTRA_INCLUDE="$4"

cd "$SRC"
rm -rf "$BUILD"

python -m mesonbuild.mesonmain setup "$BUILD" . \
    --cross-file switch_cross_file.txt \
    --prefix "$PREFIX" \
    --libdir 'opt/devkitpro/portlibs/switch' \
    -Dplatforms=switch \
    -Dgallium-drivers=nouveau \
    -Dbuild-tests=false \
    -Dllvm=disabled \
    -Db_lto=false \
    --buildtype=release

echo "setup done: $BUILD"