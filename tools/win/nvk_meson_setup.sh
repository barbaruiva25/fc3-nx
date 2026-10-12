#!/bin/bash
# Full cross build of mesa-switch -> a static libvulkan.a for the Switch NRO.
#
# Run by tools/win/build_nvk.ps1. Which commit matters: the NVK driver and the Horizon backend are NOT on this
# fork's `main` any more. They exist at the commit the other Switch ports build from:
#
#     git checkout 1a8c1a66d6fd8d65f10107c4627ffc3606ba5631   (Mesa 26.2.x, nvkmd/switch + nouveau/horizon)
#
# The nfsmw-nx patch (mesa/mesa-switch-nfsmw.patch) then applies on top and gives the driver changes the released
# NROs have (ZCULL, cheaper draws, set 4 by differences, uncached memory, the NAK scheduling fixes).
#
#   bash nvk_meson_setup.sh <source> <builddir> <install-prefix> <host-python>
#
# ALL FOUR ARGUMENTS ARE MSYS2 PATHS. The cross file names its compilers as /opt/devkitpro/..., so meson has to run
# as MSYS2's Python: with the Windows Python the paths do not resolve and the first error is a misleading
# "prefix ... must be an absolute path".
set -e
export PATH="/usr/bin:/bin:$PATH"

SRC="$1"
BUILD="$2"
PREFIX="$3"
EXTRA_INCLUDE="$4"

cd "$SRC"
rm -rf "$BUILD"

# ---------------------------------------------------------------------------------------------
# Ferramentas que o meson procura no PATH
# ---------------------------------------------------------------------------------------------

# glslangValidator compiles src/nouveau/vulkan/nvkcl.spv. Without it the setup says
# "Program glslangValidator found: NO" and the build dies on that .spv. fc3-nx already builds one for
# the PC build (tools/win/build_glslang.ps1 -> out/glslang/StandAlone); SPIR-V is portable, so the
# same Windows binary serves the cross build.
FC3=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx
GLSLANG="$FC3/out/glslang/StandAlone"
if [ -x "$GLSLANG/glslangValidator.exe" ]; then
    export PATH="$GLSLANG:$PATH"
    echo "glslangValidator: $GLSLANG"
else
    echo "AVISO: glslangValidator nao encontrado em $GLSLANG; nvkcl.spv vai falhar." >&2
    echo "       Construa antes com tools/win/build_glslang.ps1" >&2
fi

# meson.build:972 runs find_program('mesa_clc', native: true) and find_program('vtn_bindgen2') whenever
# mesa-clc=system - even though with_clc comes out false here (meson.build:957-960 and 971-975: no CLC
# driver, and gallium-rusticl is off). find_program only needs the file to exist and be executable, and
# with_clc=false means nothing ever runs it, so two stubs satisfy it. They fail loudly if something does.
# mesa-switch/build-switch.sh builds the real ones in a NATIVE build; that needs a host LLVM matching
# Mesa 26.2, which is not installed here (only clang 23.1.3). See tools/win/clc_stub.sh.
STUB_DIR="${STUB_DIR:-$FC3/out/tools/clc}"
STUB_SRC="$FC3/tools/win/clc_stub.sh"
mkdir -p "$STUB_DIR"
for name in mesa_clc vtn_bindgen2; do
    cp "$STUB_SRC" "$STUB_DIR/$name"
    chmod +x "$STUB_DIR/$name"
done
export PATH="$STUB_DIR:$PATH"

# ---------------------------------------------------------------------------------------------
# meson setup
# ---------------------------------------------------------------------------------------------

# The flags below are mesa-switch's own build-switch.sh, the recipe this tree is meant to be built with.
# The ones that were missing before, and why each mattered:
#
#   -Dvulkan-drivers=nouveau   Without it meson generates NO Vulkan target at all. The value is "nouveau",
#                               not "nvk" (docs/fc3/NOTAS-DE-BUILD.md §10 says meson rejects nvk - true, but
#                               the driver is selected by this flag and it was never in this script).
#   -Degl=disabled -Dopengl=false -Dgles1=disabled -Dgles2=disabled -Dglx=disabled
#                               src/egl/meson.build:155 errors out with "Switch EGL requires the nouveau
#                               Gallium driver" for any platform=switch build. That is what forced the
#                               Gallium nouveau driver in, and the Gallium driver is the half of the tree
#                               whose headers disagree (nouveau_winsys.h). Turning GL and EGL off leaves
#                               only the Vulkan half, which is all the NRO needs.
#   -Dmesa-clc=system -Dprecomp-compiler=system
#                               With these, meson.build:957-960 leaves with_drivers_clc false and
#                               meson.build:971-975 leaves with_clc = with_gallium_rusticl (off), so the
#                               cross build skips LLVM entirely. Any other value makes with_clc true and
#                               the setup dies with "Feature llvm cannot be enabled: CLC requires LLVM"
#                               (meson.build:983).
#   --default-library=static   The NRO links a static libvulkan.a. Shared makes the zlib subproject try
#                               to link a .so cross-compiled, which fails with "undefined reference to
#                               `main'".
# --libdir e RELATIVO ao prefix: tem de terminar em /lib, senao os .a caem direto em
# .../portlibs/switch/ e o build_switch.ps1 (que espera <NVK_SDK>/lib/libvulkan.a, como
# sdk/cmake/rexglue_switch.cmake:16 exige) nao acha. Aconteceu uma vez; os .a foram movidos a mao.
/usr/bin/python -m mesonbuild.mesonmain setup "$BUILD" . \
    --cross-file switch_cross_file.txt \
    --prefix "$PREFIX" \
    --libdir 'opt/devkitpro/portlibs/switch/lib' \
    -Dplatforms=switch \
    -Dvulkan-drivers=nouveau \
    -Dgallium-drivers=nouveau \
    -Dshader-cache=true \
    -Dgallium-rusticl=false \
    -Dglx=disabled \
    -Degl=disabled \
    -Dopengl=false \
    -Dgles1=disabled \
    -Dgles2=disabled \
    -Dshared-glapi=disabled \
    -Dllvm=disabled \
    -Dshared-llvm=disabled \
    -Dmesa-clc=system \
    -Dprecomp-compiler=system \
    -Dcpp_rtti=false \
    -Dbuild-tests=false \
    -Db_lto=false \
    -Db_ndebug=true \
    --default-library=static \
    --buildtype=release

echo "setup done: $BUILD"