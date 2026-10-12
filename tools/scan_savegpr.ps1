# Audita o codegen: funcoes que USAM r28..r31 maswhose prologo nao os salva.
#
# No Xbox 360 os helpers __savegprlr_N salvam r14..rN. Uma funcao que escreve r28..r31 e chama
# __savegprlr_27 (ou menos) viola a ABI do PowerPC: quem altera um registrador nao-volátil precisa
# salvar. No hardware o codigo do Xbox nunca faz isso, entao o erro e do gerador (ou da assinatura
# extraida do XEX), nao do jogo.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File out\scan_savegpr.ps1
param([string]$Dir = "$PSScriptRoot\..\app\generated\default")
$files = Get-ChildItem $Dir -Filter *.cpp
$bad = New-Object System.Collections.Generic.List[object]
$stats = @{}
foreach ($f in $files) {
    $lines = [System.IO.File]::ReadAllLines($f.FullName)
    $fn = $null; $saves = -1; $uses = $false; $max = 0
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $L = $lines[$i]
        if ($L -match '^DEFINE_REX_FUNC\((\w+)\) \{') {
            if ($fn -and $saves -ge 0) {
                $key = "save$saves"
                if (-not $stats.ContainsKey($key)) { $stats[$key] = 0 }
                $stats[$key]++
                if ($max -gt $saves) {
                    $bad.Add([pscustomobject]@{
                        Func = $fn; File = $f.Name; Line = ($i - $saves); Saves = $saves
                        UsesUpTo = $max
                    })
                }
            }
            $fn = $Matches[1]; $saves = -1; $uses = $false; $max = 0
            continue
        }
        if (-not $fn) { continue }
        if ($saves -lt 0 -and $L -match '__savegprlr_(\d+)\(ctx, base\)') { $saves = [int]$Matches[1] }
        # escrita (atribuicao) em r28..r31, dentro do corpo
        if ($L -match 'ctx\.(r28|r29|r30|r31)\.(s64|u64|s32|u32)\s*=') {
            $uses = $true
            $r = [int]$Matches[1].Substring(1)
            if ($r -gt $max) { $max = $r }
        }
    }
    if ($fn -and $saves -ge 0) {
        $key = "save$saves"
        if (-not $stats.ContainsKey($key)) { $stats[$key] = 0 }
        $stats[$key]++
        if ($max -gt $saves) {
            $bad.Add([pscustomobject]@{ Func = $fn; File = $f.Name; Line = 0; Saves = $saves; UsesUpTo = $max })
        }
    }
}
Write-Output "=== funcoes por helper de salvamento ==="
$stats.GetEnumerator() | Sort-Object Name | ForEach-Object { "  {0,-12} {1}" -f $_.Key, $_.Value }
Write-Output ""
Write-Output ("=== violacoes: usam r28..r31 acima do que salvam: {0} ===" -f $bad.Count)
$bad | Sort-Object -Property @{Expression={$_.Saves}; Ascending=$true} | Select-Object -First 40 |
    Format-Table Func, Saves, UsesUpTo, File -AutoSize