# Reproduz o probe de sanidade do Rust do meson, que falha, para ver o erro do linker.
#
# O meson chama:
#   rustc-switch-wrapper.sh -C linker=/opt/devkitpro/.../gcc --emit link=sanity_... -o ...exe <f>.rs --print sysroot
# O wrapper troca o linker por um nativo so nesse probe. A linkagem e que falha.
export PATH="/usr/bin:/bin:$PATH"
MESA=/c/Users/barba/Documents/xbox360/FARCRY3/xbox360/mesa-switch
export MESA_SWITCH_RUSTC="/c/Users/barba/.cargo/bin/rustc.exe"
export MESA_SWITCH_RUST_TARGET=aarch64-unknown-linux-gnu

cat > /tmp/sanity_check_for_rust.rs <<'EOF'
fn main() {}
EOF

echo "== wrapper com os mesmos args do meson =="
"$MESA/rustc-switch-wrapper.sh" \
    -C linker=/opt/devkitpro/devkitA64/bin/aarch64-none-elf-gcc \
    --emit link=sanity_check_for_rust \
    -o /tmp/sanity_check_for_rust_cross.exe \
    /tmp/sanity_check_for_rust.rs 2>&1 | head -25

echo
echo "== o rustc puro, sem wrapper, para host =="
"$MESA_SWITCH_RUSTC" -C linker=/c/msys64/mingw64/bin/gcc.exe \
    --emit link=sanity_check_for_rust -o /tmp/s2.exe /tmp/sanity_check_for_rust.rs 2>&1 | head -12

echo
echo "== rustc puro com o default (sem -C linker) =="
"$MESA_SWITCH_RUSTC" -o /tmp/s3.exe /tmp/sanity_check_for_rust.rs 2>&1 | head -8
ls -l /tmp/s3.exe 2>&1 | head -1