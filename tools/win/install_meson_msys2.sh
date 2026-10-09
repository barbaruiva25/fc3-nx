#!/bin/bash
# Installs the Python packages Mesa's build needs into devkitPro's MSYS2: meson, setuptools (for distutils, gone in
# 3.12), mako (generates the SPIR-V headers) and markupsafe (mako's dependency).
#
# MSYS2's Python has no pip and `python -m ensurepip` fails there, so the wheels are downloaded on the Windows Python
# (done by tools/win/build_nvk.ps1 before calling this) and unpacked here. Everything is pure Python, so a wheel that
# works on Windows works here; markupsafe has a C speed-up but falls back to Python without it.
#
#   bash install_meson_msys2.sh <wheel-dir>
set -e

WHEELS="${1:?usage: install_meson_msys2.sh <wheel-dir>}"
SITE=/usr/lib/python3.12/site-packages
PY=/usr/bin/python

mkdir -p "$SITE"

for w in "$WHEELS"/*.whl; do
    [ -e "$w" ] || continue
    name=$(basename "$w")
    case "$name" in
        *win_amd64*|*win32*|*linux_x86_64*|*macosx*)
            echo "skipping platform-specific wheel: $name"
            continue
            ;;
    esac
    echo "unpacking $name"
    # unzip is not always present; python's zipfile always is.
    "$PY" -m zipfile -e "$w" "$SITE"
done

# markupsafe and PyYAML have no usable pure wheel (their wheels carry a compiled speed-up / extension), so they come
# from the sdists, unpacked by tools/win/unpack_markupsafe.py and unpack_pyyaml.py into <wheels>/ms_site on the
# Windows side. yaml goes to site-packages root (the package is `yaml`), markupsafe likewise.
if [ -d "$WHEELS/ms_site" ]; then
    echo "== copying pure-python packages from the sdists"
    for pkg in markupsafe yaml; do
        if [ -d "$WHEELS/ms_site/$pkg" ]; then
            cp -r "$WHEELS/ms_site/$pkg" "$SITE/"
            echo "  $pkg"
        fi
    done
fi

echo "== checking"
"$PY" -c 'import mesonbuild, setuptools, mako, markupsafe, yaml; print("meson + setuptools + mako + markupsafe + pyyaml OK")'
"$PY" -m mesonbuild.mesonmain --version