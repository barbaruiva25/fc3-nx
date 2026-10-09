# Builds NVK, the Vulkan driver the Switch NRO carries, as a static libvulkan.a.
#
# The Switch has no Vulkan driver homebrew can use, so the NRO links one in. tools\win\build_switch.ps1 links
# whatever is under $NVK_SDK; this script puts it in <repo>/mesa-switch-install and prints the NVK_SDK line to use.
#
# WHICH COMMIT: the NVK driver and the Horizon backend are not on this fork's `main` any more (checked: `main` has no
# src/vulkan/nvk and meson rejects -Dvulkan-drivers=nvk). They exist at 1a8c1a66d6fd8d65f10107c4627ffc3606ba5631,
# the commit nfsmw-nx's mesa/README.md names. On that commit the layout is src/nouveau/vulkan/nvkmd/{nouveau,switch}
# and src/nouveau/horizon/, and meson picks the driver itself, so no -D flag is needed.
#
# WHY MSYS2 AND NOT POWERSHELL: mesa-switch's cross files use MSYS2 paths (/opt/devkitpro/...) and its build is bash.
# devkitPro's MSYS2 has bash, ninja, python and the devkitA64 cross compiler. Rust (for the NAK shader compiler) comes
# from a normal Windows rustup with the GNU toolchain; the MSYS2 shell can call it.
#
# WHY NOT THE REPO'S OWN build-switch.sh: that one runs the cross build inside Docker, and Docker is not installed
# here. This drives the same build directly.
#
# The nfsmw-nx patch (mesa/mesa-switch-nfsmw.patch) is applied by hand before this runs, and is what gives the driver
# changes the released NROs have. Without it the driver still builds and runs, just slower, with a known shader bug.
#
# Hours, not minutes: Mesa is large and Horizon is not a fast configuration. Run once.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\win\build_nvk.ps1 [-Jobs 20] [-Reuse]
param(
    # The mesa-switch checkout, already at the NVK commit.
    [string]$Mesa = 'C:\Users\barba\Documents\xbox360\mesa-switch',
    # Parallel jobs inside meson (0 = every logical processor).
    [int]$Jobs = 0,
    # Reuse the existing build directory (skip meson setup).
    [switch]$Reuse
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$install = Join-Path $root 'mesa-switch-install'
$builddir = Join-Path $root 'out\mesa'
$log = Join-Path $root 'out\nvk_build.log'
$bash = 'C:\devkitPro\msys2\usr\bin\bash.exe'

if (-not (Test-Path (Join-Path $Mesa 'meson.build'))) { throw "$Mesa is not a mesa-switch checkout" }
if (-not (Test-Path $bash)) { throw 'devkitPro MSYS2 not found' }
# The commit is the whole point: check rather than build for hours and find out at the end.
if (-not (Test-Path (Join-Path $Mesa 'src\nouveau\vulkan\nvkmd\switch'))) {
    throw ("$Mesa has no nvkmd/switch: it is not at commit 1a8c1a66d6f. " +
           'git checkout 1a8c1a66d6fd8d65f10107c4627ffc3606ba5631 in that tree first.')
}
New-Item -ItemType Directory -Force (Join-Path $root 'out') | Out-Null

$jobs = if ($Jobs -gt 0) { $Jobs } else { [Environment]::ProcessorCount }

# Windows path -> MSYS2 path (C:\x\y -> /c/x/y). The cross file's own binaries stay as it declares them.
function ToMsys([string]$p) { ($p -replace '\\', '/') -replace '^([A-Za-z]):', '/$1' }
$msysMesa = ToMsys $Mesa
$msysBuild = ToMsys $builddir
$msysInstall = ToMsys $install

function RunBash([string]$script, [string[]]$scriptArgs, [string]$what) {
    "== $what" | Write-Host
    # bash <file> <args...>: no nested quoting, which is what broke the first attempt (meson setup silently created
    # nothing because cmd.exe ate the line).
    & $bash $script $scriptArgs *>> $log
    if ($LASTEXITCODE) {
        Write-Host "--- last 30 lines of out\nvk_build.log ---"
        Get-Content $log -Tail 30
        throw "$what failed (exit $LASTEXITCODE)"
    }
}

Remove-Item $log -ErrorAction SilentlyContinue
New-Item -ItemType File -Force $log | Out-Null

$setupScript = Join-Path $PSScriptRoot 'nvk_meson_setup.sh'
$buildScript = Join-Path $PSScriptRoot 'nvk_meson_build.sh'

# The prefix must exist before setup, and meson validates it.
New-Item -ItemType Directory -Force $install | Out-Null

if (-not ($Reuse -and (Test-Path (Join-Path $builddir 'build.ninja')))) {
    RunBash $setupScript @($msysMesa, $msysBuild, $msysInstall) 'meson setup'
} else {
    "== meson setup skipped (-Reuse)" | Write-Host
}

RunBash $buildScript @($msysMesa, $msysBuild, "$jobs") "meson compile + install ($jobs jobs)"

$lib = Join-Path $install 'opt\devkitpro\portlibs\switch\lib\libvulkan.a'
if (-not (Test-Path $lib)) {
    Write-Host 'libvulkan.a not at the expected path; what the install produced:'
    Get-ChildItem $install -Recurse -Filter '*.a' -ErrorAction SilentlyContinue |
        Select-Object -First 20 FullName, @{n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) }}
    throw 'no libvulkan.a in the install prefix'
}
Write-Host ''
Write-Host ("libvulkan.a: {0:N1} MB" -f ((Get-Item $lib).Length / 1MB))
Write-Host 'Build the NRO with:'
Write-Host "  `$env:NVK_SDK = '$install\opt\devkitpro\portlibs\switch'"
Write-Host '  powershell -NoProfile -ExecutionPolicy Bypass -File tools\win\build_switch.ps1'