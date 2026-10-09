#!/bin/bash
# Full cross build of mesa-switch -> static libvulkan.a for the Switch NRO.
# Run by tools/win/build_nvk.ps1. See nvk_meson_setup.sh for which commit has the NVK driver.
#
#   bash nvk_meson_build.sh <source> <builddir> <jobs> <host-python>
#
# HOST PYTHON: the Ninja commands Mesa runs (the mako templates that generate the SPIR-V headers) need meson's
# Python with mako + setuptools + markupsafe. devkitPro's MSYS2 has meson (installed into it by hand) but pip cannot
# install packages there, so the setuptools/mako/markupsafe chain is on the normal Windows Python instead, and that
# interpreter is put first on PATH for the build. It only generates files; it never compiles for the target.
set -e

SRC="$1"
BUILD="$2"
JOBS="$3"
HOST_PY="$4"

export PATH="$(dirname "$HOST_PY"):$PATH"

cd "$SRC"
python -m mesonbuild.mesonmain compile -C "$BUILD" -j "$JOBS"
python -m mesonbuild.mesonmain install -C "$BUILD" --only-changed

echo "build+install done"
echo "== libraries"
find "$BUILD" \( -name 'libvulkan.a' -o -name 'libnvk.a' -o -name 'libnak*.a' \) -exec ls -la {} \;