# Loads the Windows build environment of the Far Cry 3 port into the current PowerShell session:
#   MSVC x64 libraries and Windows SDK (VS 2022 Build Tools, for clang's msvc target),
#   LLVM clang (ReXGlue needs clang), and one single CMake + Ninja.
#
#   . tools\win\env.ps1
#
# Override the locations with $env:FC3_LLVM, $env:FC3_VSDIR and $env:FC3_CMAKE_DIR if yours differ.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# LLVM: a portable copy next to the repo (default), the winget/system install, or $env:FC3_LLVM.
$llvm = if ($env:FC3_LLVM) { $env:FC3_LLVM }
        elseif (Test-Path (Join-Path $root '..\_tools\llvm\bin\clang++.exe')) { Join-Path $root '..\_tools\llvm' }
        else { 'C:\Program Files\LLVM' }

$vs = if ($env:FC3_VSDIR) { $env:FC3_VSDIR } else { 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools' }
$cm = if ($env:FC3_CMAKE_DIR) { $env:FC3_CMAKE_DIR } else { Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake' }

$llvm = (Resolve-Path $llvm).Path
if (-not (Test-Path "$llvm\bin\clang++.exe")) { throw "clang not found in $llvm\bin" }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
if (-not (Test-Path $vcvars)) { throw "vcvars64.bat not found under $vs" }

if (-not $env:FC3_ENV_LOADED) {
    # devkitPro puts MSYS2's usr/bin on PATH, which has its own `cmd`, `link` and `find`: keep it out of this
    # session, and call Windows' cmd.exe by its full path.
    $env:PATH = (($env:PATH -split ';') | Where-Object { $_ -and $_ -notmatch 'msys2\\usr\\bin' }) -join ';'
    $env:PATH = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer;$env:PATH"
    & $env:ComSpec /c "`"$vcvars`" >nul && set" | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($Matches[1])" -Value $Matches[2] }
    }
    if (-not $env:VCToolsInstallDir) { throw "vcvars64.bat did not set up MSVC" }
    $env:PATH = "$llvm\bin;$cm\CMake\bin;$cm\Ninja;$env:PATH"
    $env:CC = 'clang'
    $env:CXX = 'clang++'
    # tools\codegen.ps1 and tools\win\package_switch.ps1 call `python` by name. On Windows the first `python` on PATH
    # is usually the Microsoft Store alias (WindowsApps\python.exe), which opens the Store instead of running, and
    # post_codegen.py then fails without a traceback. Put the real interpreter first; FC3_PYTHON overrides.
    $py = if ($env:FC3_PYTHON) { $env:FC3_PYTHON } else {
        Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python3*\python.exe') -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1 | ForEach-Object { $_.DirectoryName }
    }
    if ($py -and (Test-Path (Join-Path $py 'python.exe'))) { $env:PATH = "$py;$env:PATH" }
    # The reXGlue code generator links with the MSVC driver; keep clang from picking lld-link, which does not
    # understand the MSVC import-library flags the SDK's compiler checks pass.
    Remove-Item Env:LLD_LINK -ErrorAction SilentlyContinue
    $env:FC3_ENV_LOADED = '1'
}
$ErrorActionPreference = 'Continue'