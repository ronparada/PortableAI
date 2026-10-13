param([Parameter(Mandatory=$true)][string]$LabRoot,[int]$Port=18765)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $LabRoot -ErrorAction Stop).Path).TrimEnd('\','/')
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Choose a folder for the lab.' }
$prefix=$root+[IO.Path]::DirectorySeparatorChar
function Resolve-LabPath([string]$relative) {
  if ([IO.Path]::IsPathRooted($relative)) { throw 'Use a path relative to the lab folder.' }
  $candidate=[IO.Path]::GetFullPath((Join-Path $root $relative))
  if ($candidate -ne $root -and -not $candidate.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Path is outside the lab folder.' }
  $walk=$root
  foreach ($part in ($relative -split '[\\/]')) {
    if (-not $part -or $part -eq '.') { continue }
    $walk=Join-Path $walk $part
    if (Test-Path -LiteralPath $walk) {
      $item=Get-Item -LiteralPath $walk -Force
      if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Links and junctions are not allowed in the lab folder.' }
    }
  }
  return $candidate
}
function Get-LabFiles([string]$folder) {
  $pending=[Collections.Generic.Queue[string]]::new()
  $pending.Enqueue($folder)
  while ($pending.Count) {
    $current=$pending.Dequeue()
    foreach ($item in (Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue)) {
      if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
      if ($item.PSIsContainer) { $pending.Enqueue($item.FullName) }
      else { $item }
    }
  }
}
function Invoke-LabTool([string]$name,$arguments) {
  switch ($name) {
    'find_files' {
      $pattern=[string]$arguments.pattern; if (-not $pattern) { $pattern='*' }
      $matches=Get-LabFiles $root |
        Where-Object { $_.Name -like $pattern } |
        Select-Object -First 100
      return (@($matches | ForEach-Object { [pscustomobject]@{path=$_.FullName.Substring($prefix.Length);bytes=$_.Length;hidden=[bool]($_.Attributes -band [IO.FileAttributes]::Hidden)} }) | ConvertTo-Json -Compress -Depth 4)
    }
    'read_text' {
      $path=Resolve-LabPath ([string]$arguments.path)
      $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
      if ($item.PSIsContainer -or $item.Length -gt 65536) { throw 'Only text files up to 64 KB can be read.' }
      return (Get-Content -LiteralPath $path -Raw -ErrorAction Stop)
    }
    'plan_screenshot_sort' {
      $relative=[string]$arguments.folder; if (-not $relative) { $relative='.' }
      $folder=Resolve-LabPath $relative
      if (-not (Test-Path -LiteralPath $folder -PathType Container)) { throw 'Screenshot folder not found.' }
      $items=Get-ChildItem -LiteralPath $folder -File -Force | Where-Object { $_.Extension -in @('.png','.jpg','.jpeg','.webp','.bmp') }
      $plan=@($items | ForEach-Object { [pscustomobject]@{from=$_.FullName.Substring($prefix.Length);to=(Join-Path ($relative.TrimEnd('\','/')) ($_.CreationTime.ToString('yyyy-MM')+'\'+$_.Name)).TrimStart('\','/') } })
      $script:pendingPlan=$plan
      return ($plan | Select-Object -First 100 | ConvertTo-Json -Compress -Depth 4)
    }
    default { throw "Unsupported tool: $name" }
  }
}
$tools=@(
  @{type='function';function=@{name='find_files';description='Find files by wildcard name inside the selected lab folder, including hidden files. Maximum 100 results.';parameters=@{type='object';properties=@{pattern=@{type='string';description='Filename wildcard such as *flag*'}};required=@('pattern')}}},
  @{type='function';function=@{name='read_text';description='Read a small text file inside the selected lab folder using a relative path.';parameters=@{type='object';properties=@{path=@{type='string'}};required=@('path')}}},
  @{type='function';function=@{name='plan_screenshot_sort';description='Preview sorting images from a lab subfolder into year-month subfolders. This never moves files.';parameters=@{type='object';properties=@{folder=@{type='string';description='Relative folder such as Screenshots or .'}};required=@('folder')}}}
)
$systemMessage="You are a local lab assistant. You can search and read only inside the selected lab folder. Use tools for file questions; never invent search results. To organize screenshots, call plan_screenshot_sort and describe the preview. Do not claim files were moved. The user can type /apply to approve the pending move plan. Selected lab folder: $root"
$messages=[Collections.Generic.List[object]]::new()
$messages.Add(@{role='system';content=$systemMessage})
$script:pendingPlan=@()
Write-Host "Lab Assistant ready. Folder: $root" -ForegroundColor Green
Write-Host 'Ask a question, type /apply to approve the last sort preview, or /exit.'
while ($true) {
  $inputText=Read-Host 'Lab'
  if ($inputText -eq '/exit') { break }
  if ($inputText -eq '/apply') {
    if (-not $script:pendingPlan.Count) { Write-Host 'No pending sort plan.'; continue }
    Write-Host "Move $($script:pendingPlan.Count) file(s) as previewed? Type MOVE to confirm."
    if ((Read-Host 'Confirm') -ne 'MOVE') { Write-Host 'Cancelled.'; continue }
    $moved=0
    foreach ($entry in $script:pendingPlan) {
      $source=Resolve-LabPath $entry.from; $destination=Resolve-LabPath $entry.to
      if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or (Test-Path -LiteralPath $destination)) { continue }
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
      Move-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
      $moved++
    }
    $script:pendingPlan=@()
    Write-Host "Moved $moved file(s)."; continue
  }
  if (-not $inputText) { continue }
  $messages.Add(@{role='user';content=$inputText})
  try {
    for ($round=0; $round -lt 5; $round++) {
      $body=@{model='portable-ai';messages=@($messages);tools=$tools;tool_choice='auto';temperature=0;max_tokens=512} | ConvertTo-Json -Depth 20
      $response=Invoke-RestMethod "http://127.0.0.1:$Port/v1/chat/completions" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 180
      $message=$response.choices[0].message
      if ($message.tool_calls) {
        $messages.Add(@{role='assistant';content=$message.content;tool_calls=$message.tool_calls})
        foreach ($call in $message.tool_calls) {
          try { $argsObject=$call.function.arguments | ConvertFrom-Json; $result=Invoke-LabTool $call.function.name $argsObject }
          catch { $result="Tool error: $_" }
          Write-Host "[$($call.function.name)] $result" -ForegroundColor DarkCyan
          $messages.Add(@{role='tool';tool_call_id=$call.id;content=[string]$result})
        }
      } else { Write-Host $message.content; $messages.Add(@{role='assistant';content=$message.content}); break }
    }
  } catch { Write-Host "Request failed: $_" -ForegroundColor Red }
}
