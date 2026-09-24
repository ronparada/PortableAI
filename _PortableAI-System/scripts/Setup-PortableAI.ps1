param([ValidateSet('all','qwen','hermes')][string]$Install,[switch]$NoPause)
$ErrorActionPreference = 'Stop'
$systemRoot = Split-Path -Parent $PSScriptRoot
$root = Split-Path -Parent $systemRoot
$runtimeRoot = Join-Path $systemRoot 'runtime'; $modelRoot = Join-Path $systemRoot 'models'; $downloadRoot = Join-Path $systemRoot 'downloads'
New-Item -ItemType Directory -Force -Path $runtimeRoot,$modelRoot,$downloadRoot | Out-Null
function Wait-AtEnd { if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null } }
function Get-Choice {
  if ($Install) { return $Install }
  Write-Host ''; Write-Host 'Portable Offline Chat - first-time setup' -ForegroundColor Cyan
  Write-Host ''
  Write-Host '1. Standard setup: Qwen 3 4B only (recommended, about 2.7 GB)'
  Write-Host '2. Complete setup: Qwen 3 4B + Nous Hermes 3 3B model (about 4.7 GB)'
  Write-Host '3. Nous Hermes 3 3B model only (about 2.2 GB)'
  $answer = Read-Host 'Choose 1, 2, or 3 [1]'
  switch ($answer) { '2' {'all'} '3' {'hermes'} default {'qwen'} }
}
function Get-Download([string]$Url,[string]$Destination,[string]$Sha256) {
  $acceptedHashes=@($Sha256.ToUpperInvariant().Split(',',[StringSplitOptions]::RemoveEmptyEntries))
  if (Test-Path -LiteralPath $Destination) {
    $current=(Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    if ($current -in $acceptedHashes) { Write-Host "Already verified: $(Split-Path -Leaf $Destination)" -ForegroundColor Green; return }
    Remove-Item -LiteralPath $Destination -Force
  }
  $partial="$Destination.part"; Write-Host "Downloading $(Split-Path -Leaf $Destination)..."
  & curl.exe -L --fail --retry 3 --retry-delay 3 -C - -o $partial $Url
  if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url" }
  Move-Item -LiteralPath $partial -Destination $Destination -Force
  $actual=(Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
  if ($actual -notin $acceptedHashes) { Remove-Item -LiteralPath $Destination -Force; throw "Safety check failed for $(Split-Path -Leaf $Destination)." }
}
function Add-WindowsRuntimeSupport([string]$Target,[string]$Name) {
  $architecture=if ($Name -match 'arm64') {'arm64'} else {'x64'}
  $support=Join-Path $systemRoot "support\windows-$architecture-vc-runtime"
  if (Test-Path -LiteralPath $support) {
    Get-ChildItem -LiteralPath $support -Filter '*.dll' -File | Copy-Item -Destination $Target -Force
  } elseif ($architecture -eq 'arm64') {
    Write-Host 'Note: Windows ARM64 may require the Microsoft Visual C++ runtime on the computer.' -ForegroundColor Yellow
  }
}
function Install-Zip([string]$Url,[string]$Sha256,[string]$Name,[string]$Target) {
  $server=Join-Path $Target 'llama-server.exe'
  if (Test-Path -LiteralPath $server) { Add-WindowsRuntimeSupport $Target $Name; Write-Host "Runtime is already present: $Name" -ForegroundColor Green; return }
  $archive=Join-Path $downloadRoot "$Name.zip"; Get-Download $Url $archive $Sha256
  if (Test-Path -LiteralPath $Target) { Remove-Item -LiteralPath $Target -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $Target | Out-Null
  Expand-Archive -LiteralPath $archive -DestinationPath $Target -Force
  if (-not (Test-Path -LiteralPath $server)) { throw "llama-server.exe was not found after extracting $Name." }
  Add-WindowsRuntimeSupport $Target $Name
}
function Install-Model([string]$Url,[string]$Sha256,[string]$FileName) { Get-Download $Url (Join-Path $modelRoot $FileName) $Sha256 }
try {
  $choice=Get-Choice
  if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
    Install-Zip 'https://github.com/ggml-org/llama.cpp/releases/download/b10964/llama-b10964-bin-win-cpu-arm64.zip' '4B6A004B076EEA47C318BEA35CF1DB2FF2BF037738B04645646AE8D7C3159478' 'windows-arm64-cpu' (Join-Path $runtimeRoot 'windows-arm64-cpu')
  } else {
    Install-Zip 'https://github.com/ggml-org/llama.cpp/releases/download/b10964/llama-b10964-bin-win-vulkan-x64.zip' '1EE3AD952F4BA71F438BD6D7BEBEF19E1C7AF04ADCAA35D08B4DDABB27D4C642' 'windows-x64-vulkan' (Join-Path $runtimeRoot 'windows-x64-vulkan')
    Install-Zip 'https://github.com/ggml-org/llama.cpp/releases/download/b10964/llama-b10964-bin-win-cpu-x64.zip' '917F39C076402C421224824607397AF20F53625A60DEFC20E8DD22446BF4C5D7' 'windows-x64-cpu' (Join-Path $runtimeRoot 'windows-x64-cpu')
  }
  if ($choice -in @('all','qwen')) {
    Install-Model 'https://huggingface.co/bartowski/Qwen_Qwen3-4B-GGUF/resolve/main/Qwen_Qwen3-4B-Q4_K_M.gguf?download=true' 'FBE1D5EDD4CE802AE3AE7C7E4AB7D09789D697FDAC1FC7929F8DF4CA3C41BAE3,7485FE6F11AF29433BC51CAB58009521F205840F5B4AE3A32FA7F92E8534FDF5' 'Qwen3-4B-Q4_K_M.gguf'
  }
  if ($choice -in @('all','hermes')) {
    Install-Model 'https://huggingface.co/bartowski/Hermes-3-Llama-3.2-3B-GGUF/resolve/main/Hermes-3-Llama-3.2-3B-Q4_K_M.gguf?download=true' '2E220A14BA4328FEE38CF36C2C068261560F999FADB5725CE5C6D977CB5126B5' 'Hermes-3-Llama-3.2-3B-Q4_K_M.gguf'
  }
  Write-Host ''; Write-Host 'Portable chat setup finished.' -ForegroundColor Green
  Write-Host 'You may disconnect from the internet. Return to your operating-system folder and open a START file.'
  Wait-AtEnd
} catch { Write-Host ''; Write-Host $_ -ForegroundColor Red; Wait-AtEnd; exit 1 }
