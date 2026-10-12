# Roda o comando real do nak e hexdumpa as linhas -I do dump, para ver o backslash de verdade.
export PATH="/usr/bin:/bin:$PATH"
export MESA_SWITCH_BINDGEN=/c/Users/barba/.cargo/bin/bindgen.exe
export DEVKITPRO=/opt/devkitpro
export MESA_SWITCH_DEBUG_ARGS=/tmp/args_nak3.txt
rm -f /tmp/args_nak3.txt
cd /c/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx/out/mesa || exit 1
CMD=$(sed -n '5526p' build.ninja | sed 's/^ *COMMAND = //')
eval "$CMD" > /tmp/nak3_out.txt 2>&1
echo "bindgen exit=$?"
echo "== dump mtime =="
ls -l /tmp/args_nak3.txt
echo "== linhas com 'mesa.src' ou 'switch.src' (od) =="
grep -a 'src' /tmp/args_nak3.txt | grep -ai 'mesa.src\|h.src' | while IFS= read -r line; do
    echo "TXT: $line"
done
echo "== hex das 2 linhas com 'src' sozinho =="
grep -a 'src$' /tmp/args_nak3.txt | od -c | head -8