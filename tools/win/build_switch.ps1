# Builds the Nintendo Switch NRO: out\nx\fc3.nro (devkitA64 GCC + libnx, static NVK from the Mesa Horizon SDK).
# The generated code must already exist (tools\codegen.ps1 with the PC SDK): a cross build cannot run rexglue.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\win\build_switch.ps1 [-Jobs 8] [-LtoJobs 8] [-Reconfigure]
#       [-Pgo none|generate|use]
# NVK_SDK (environment) overrides the Mesa SDK folder (it must contain lib\libvulkan.a).
# -Pgo (profile-guided optimisation, 2026-10-08): generate = the instrumented NRO that collects counts on the console
# (app/src/fc3_pgo.cpp); use = the optimised NRO from the counts tools\win\pgo_merge.ps1 merged; none = neither.
# Without -Pgo the build keeps the setting it had.
param(
    [int]$Jobs = 8,
    [int]$LtoJobs = 8,
    [switch]$Reconfigure,
    [ValidateSet('', 'none', 'generate', 'use')][string]$Pgo = ''
)
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $PSScriptRoot 'env.ps1')  # VS CMake and Ninja on PATH (the compilers come from the toolchain file)
$nvk = if ($env:NVK_SDK) { $env:NVK_SDK } else {
    'C:/devkitPro/mesa-switch-main-nfsmw-source/mesa-switch-main/mesa-unified-install/opt/devkitpro/portlibs/switch' }
# devkitPro's installer exports DEVKITPRO as an MSYS path (/opt/devkitpro) that Windows CMake cannot open.
$devkitpro = if ($env:DEVKITPRO -and (Test-Path $env:DEVKITPRO)) { $env:DEVKITPRO } else { 'C:/devkitPro' }
$build = Join-Path $root 'out\nx'
$glslang = Join-Path $root 'out\glslang\StandAlone\glslangValidator.exe'  # host tool: SPIR-V is portable
if ($Reconfigure -or -not (Test-Path (Join-Path $build 'CMakeCache.txt'))) {
    & cmake -S (Join-Path $root 'app') -B $build -G Ninja -DCMAKE_BUILD_TYPE=Release `
        "-DCMAKE_TOOLCHAIN_FILE=$root\tools\switch\cmake\switch-devkitA64.cmake" `
        "-DREXGLUE_SWITCH_NVK_SDK=$nvk" "-Dfc3_GLSLANG_VALIDATOR=$glslang" "-DDEVKITPRO=$devkitpro" `
        "-DCMAKE_MAKE_PROGRAM=$((Get-Command ninja).Source)"
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
}
# GCC's lto-wrapper compiles the LTRANS partitions in parallel only through GNU make: without a make on PATH it runs
# all 512 of them one after another (about 17 minutes). env.ps1 keeps MSYS2's usr\bin off PATH (its own cmd, link
# and find), so make.exe and the three DLLs it needs get a folder of their own.
# devkitPro ships in two layouts and only the old one has <DEVKITPRO>\msys2: the current installer puts MSYS2 in
# C:\msys64 (pacman) and devkitPro under its own opt\. Probe both, plus MSYS2_ROOT, instead of assuming.
$make = Join-Path $root 'out\tools\make'
if (-not (Test-Path (Join-Path $make 'make.exe'))) {
    $candidates = @(
        (Join-Path $devkitpro 'msys2\usr\bin'),
        (Join-Path $devkitpro '..\..\usr\bin'),          # <msys2>\opt\devkitpro -> <msys2>\usr\bin
        $(if ($env:MSYS2_ROOT) { Join-Path $env:MSYS2_ROOT 'usr\bin' }),
        'C:\msys64\usr\bin'
    ) | Where-Object { $_ -and (Test-Path (Join-Path $_ 'make.exe')) }
    $src = $candidates | Select-Object -First 1
    if (-not $src) {
        throw "no make.exe found for the LTO link (looked in: $($candidates -join ', ')). " +
              'On MSYS2 it is the `make` pacman package.'
    }
    New-Item -ItemType Directory -Force $make | Out-Null
    foreach ($f in 'make.exe', 'msys-2.0.dll', 'msys-iconv-2.dll', 'msys-intl-8.dll') {
        if (Test-Path (Join-Path $src $f)) { Copy-Item -Force (Join-Path $src $f) $make }
    }
}
$env:PATH = "$make;$env:PATH"
$pgoArgs = @()
if ($Pgo) { $pgoArgs = @("-Dfc3_PGO=$(if ($Pgo -eq 'none') { '' } else { $Pgo })") }
& cmake $build "-Dfc3_SWITCH_LTO_JOBS=$LtoJobs" @pgoArgs | Out-Null
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& cmake --build $build -j $Jobs
exit $LASTEXITCODE
