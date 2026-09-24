param([switch]$NoPause)
$systemRoot=Split-Path -Parent $PSScriptRoot; $root=Split-Path -Parent $systemRoot; $dataRoot=Join-Path $systemRoot 'data'; $pidFile=Join-Path $dataRoot 'server.pid'; $port=18765
$candidateIds=@()
if (Test-Path -LiteralPath $pidFile) { $saved=Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1; if ($saved -match '^\d+$') { $candidateIds += [int]$saved } }
try { $candidateIds += (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop).OwningProcess } catch {}
$runtimePrefix=[IO.Path]::GetFullPath((Join-Path $systemRoot 'runtime')).TrimEnd('\')+'\'; $stopped=0
foreach ($candidateId in ($candidateIds | Select-Object -Unique)) {
  try {
    $process=Get-Process -Id $candidateId -ErrorAction Stop; $processPath=$process.Path
    if ($process.ProcessName -eq 'llama-server' -and $processPath -and [IO.Path]::GetFullPath($processPath).StartsWith($runtimePrefix,[StringComparison]::OrdinalIgnoreCase)) {
      Stop-Process -Id $candidateId -Force -ErrorAction Stop; Wait-Process -Id $candidateId -Timeout 10 -ErrorAction SilentlyContinue; $stopped++
    }
  } catch {}
}
$releaseDeadline=(Get-Date).AddSeconds(15)
while ((Get-Date) -lt $releaseDeadline) {
  $listenerStillPresent=$false
  try { $listenerStillPresent=[bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop) } catch {}
  if (-not $listenerStillPresent) { break }
  Start-Sleep -Milliseconds 250
}
Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
if ($stopped) { Write-Host 'Portable AI has been stopped. You may now start another model.' -ForegroundColor Green }
else { Write-Host 'No Portable AI server from this folder is running.' -ForegroundColor Cyan }
if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
