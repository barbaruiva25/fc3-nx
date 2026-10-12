# Compara os clang-args de duas regras do ninja (linhas do build.ninja), para achar o que quebra
# uma e nao a outra. Uso: probe_diff.sh <linha1> <linha2> <nome1> <nome2>
export PATH="/usr/bin:/bin:$PATH"
export MESA_SWITCH_BINDGEN=/c/Users/barba/.cargo/bin/bindgen.exe
export DEVKITPRO=/opt/devkitpro
L1=$1
L2=$2
N1=$3
N2=$4
cd /c/Users/barba/Documents/xbox360/FARCRY3/xbox360/fc3-nx/out/mesa || exit 1
for spec in "$L1:$N1" "$L2:$N2"; do
    L=${spec%%:*}
    N=${spec##*:}
    CMD=$(sed -n "${L}p" build.ninja | sed 's/^ *COMMAND = //')
    export MESA_SWITCH_DEBUG_ARGS=/tmp/args_$N.txt
    eval "$CMD" > /tmp/out_$N.txt 2>&1
    echo "$N: exit=$? args=$(wc -l < /tmp/args_$N.txt)"
done
echo "== so no $N1 (lado do clang, apos --) =="
awk '/^--$/{f=1; next} f' /tmp/args_$N1.txt | sort > /tmp/clang_$N1.txt
awk '/^--$/{f=1; next} f' /tmp/args_$N2.txt | sort > /tmp/clang_$N2.txt
comm -23 /tmp/clang_$N1.txt /tmp/clang_$N2.txt | head -30