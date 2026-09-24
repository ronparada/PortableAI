param([ValidateSet('qwen','hermes')][string]$Model='qwen',[switch]$NoBrowser,[switch]$TestOnly)
$ErrorActionPreference='Stop'
$systemRoot=Split-Path -Parent $PSScriptRoot; $root=Split-Path -Parent $systemRoot; $dataRoot=Join-Path $systemRoot 'data'; $logRoot=Join-Path $dataRoot 'logs'; $tempRoot=Join-Path $dataRoot 'temp'
New-Item -ItemType Directory -Force -Path $dataRoot,$logRoot,$tempRoot | Out-Null
$env:LLAMA_CACHE=Join-Path $dataRoot 'cache'; $env:TEMP=$tempRoot; $env:TMP=$tempRoot
$models=@{qwen='Qwen3-4B-Q4_K_M.gguf';hermes='Hermes-3-Llama-3.2-3B-Q4_K_M.gguf'}
$modelPath=Join-Path $systemRoot ('models\'+$models[$Model])
if (-not (Test-Path -LiteralPath $modelPath)) { Write-Host "The selected language model is not on the USB. Run 1-SETUP-PORTABLE-CHAT.cmd first." -ForegroundColor Red; if (-not $TestOnly) { Read-Host 'Press Enter to close' | Out-Null }; exit 1 }
$port=18765; $server=$null; $pidFile=Join-Path $dataRoot 'server.pid'
function Stop-LeftoverPortableServer {
  $candidateIds=@()
  if (Test-Path -LiteralPath $pidFile) { $saved=Get-Content -LiteralPath $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1; if ($saved -match '^\d+$') { $candidateIds += [int]$saved } }
  try { $candidateIds += (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop).OwningProcess } catch {}
  $runtimePrefix=[IO.Path]::GetFullPath((Join-Path $systemRoot 'runtime')).TrimEnd('\')+'\'
  foreach ($candidateId in ($candidateIds | Select-Object -Unique)) {
    try {
      $old=Get-Process -Id $candidateId -ErrorAction Stop
      $oldPath=$old.Path
      if ($old.ProcessName -eq 'llama-server' -and $oldPath -and [IO.Path]::GetFullPath($oldPath).StartsWith($runtimePrefix,[StringComparison]::OrdinalIgnoreCase)) {
        Write-Host 'Stopping a Portable AI server left open from the previous session...' -ForegroundColor Yellow
        Stop-Process -Id $candidateId -Force -ErrorAction Stop
        Wait-Process -Id $candidateId -Timeout 10 -ErrorAction SilentlyContinue
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
}
try {
  Stop-LeftoverPortableServer
  $activeListener=$false
  try { $activeListener=[bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop) } catch {}
  if ($activeListener) { throw "Port $port is busy. Run 4-STOP-PORTABLE-AI.cmd and try again." }
  if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $backends=@(@{Name='CPU';Path='runtime\windows-arm64-cpu';Layers='0'}) }
  else { $backends=@(@{Name='Vulkan GPU';Path='runtime\windows-x64-vulkan';Layers='99'},@{Name='CPU';Path='runtime\windows-x64-cpu';Layers='0'}) }
  $ready=$false
  foreach ($backend in $backends) {
    $exe=Join-Path $systemRoot ($backend.Path+'\llama-server.exe'); if (-not (Test-Path -LiteralPath $exe)) { continue }
    Write-Host "Loading $Model with $($backend.Name). A USB drive can take a minute..." -ForegroundColor Cyan
    $arguments=@('-m',$modelPath,'--alias','portable-ai','--host','127.0.0.1','--port',"$port",'-c','8192','-ngl',$backend.Layers,'--offline','--reasoning','off','--no-webui-mcp-proxy','--parallel','1')
    $server=Start-Process -FilePath $exe -ArgumentList $arguments -WorkingDirectory (Split-Path $exe) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logRoot 'server-out.log') -RedirectStandardError (Join-Path $logRoot 'server-error.log')
    Set-Content -LiteralPath $pidFile -Value $server.Id -Encoding Ascii
    $deadline=(Get-Date).AddMinutes(4)
    while ((Get-Date) -lt $deadline -and -not $server.HasExited) { try { $health=Invoke-RestMethod "http://127.0.0.1:$port/health" -TimeoutSec 2; if ($health.status -eq 'ok') { $ready=$true; break } } catch {}; Start-Sleep -Seconds 1 }
    if ($ready) { break }; if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
    Write-Host "$($backend.Name) did not start; trying the next available runtime." -ForegroundColor Yellow
  }
  if (-not $ready) { throw "The model did not load. See data\logs\server-error.log." }
  Write-Host "Ready: http://127.0.0.1:$port" -ForegroundColor Green
  if ($TestOnly) {
    $body=@{model='portable-ai';messages=@(@{role='user';content='Reply with exactly: OK'});max_tokens=8;temperature=0} | ConvertTo-Json -Depth 5
    $response=Invoke-RestMethod "http://127.0.0.1:$port/v1/chat/completions" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 120
    $content=$response.choices[0].message.content
    if (-not $content) { throw 'The server loaded, but the model did not return a test response.' }
    Write-Host "Model response: $($content.Trim())" -ForegroundColor Green
    return
  }
  if (-not $NoBrowser) { Start-Process "http://127.0.0.1:$port" | Out-Null }
  Write-Host 'Keep this window open while chatting.'; Read-Host 'Close the chat tab, then press Enter here to stop the AI' | Out-Null
} catch {
  Write-Host ''; Write-Host $_ -ForegroundColor Red; $errorLog=Join-Path $logRoot 'server-error.log'
  if (Test-Path -LiteralPath $errorLog) { Write-Host 'Recent server log:' -ForegroundColor Yellow; Get-Content -LiteralPath $errorLog -Tail 20 }
  if (-not $TestOnly) { Read-Host 'Press Enter to close' | Out-Null }; exit 1
} finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force }
  Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}
