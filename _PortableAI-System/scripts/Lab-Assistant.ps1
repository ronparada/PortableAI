param([Parameter(Mandatory=$true)][string]$LabRoot,[int]$Port=18765)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $LabRoot -ErrorAction Stop).Path).TrimEnd('\','/')
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Choose a folder for the lab.' }
$prefix=$root+[IO.Path]::DirectorySeparatorChar
function Test-CloudPlaceholder([string]$path) {
  $details=& fsutil reparsepoint query $path 2>$null | Out-String
  return ($details -match '(?i)0x9000[0-9a-f]01a\b')
}
function Resolve-LabPath([string]$relative,[bool]$allowCloudFile=$false) {
  if ([IO.Path]::IsPathRooted($relative)) { throw 'Use a path relative to the lab folder.' }
  $candidate=[IO.Path]::GetFullPath((Join-Path $root $relative))
  if ($candidate -ne $root -and -not $candidate.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Path is outside the lab folder.' }
  $walk=$root
  foreach ($part in ($relative -split '[\\/]')) {
    if (-not $part -or $part -eq '.') { continue }
    $walk=Join-Path $walk $part
    if (Test-Path -LiteralPath $walk) {
      $item=Get-Item -LiteralPath $walk -Force
      if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        if (-not ($allowCloudFile -and $walk -eq $candidate -and -not $item.PSIsContainer -and (Test-CloudPlaceholder $walk))) {
          throw 'Links and junctions are not allowed in the lab folder.'
        }
      }
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
      if ($item.PSIsContainer) {
        if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $pending.Enqueue($item.FullName) }
      }
      else { $item }
    }
  }
}
function Invoke-LabTool([string]$name,$arguments) {
  switch ($name) {
    'find_files' {
      $pattern=[string]$arguments.pattern; if (-not $pattern) { $pattern='*' }
      if ($pattern -notmatch '[*?]') { $pattern="*$pattern*" }
      $matches=@(Get-LabFiles $root |
        Where-Object { $_.Name -like $pattern } |
        Select-Object -First 100)
      $files=@($matches | ForEach-Object { [pscustomobject]@{path=$_.FullName.Substring($prefix.Length);bytes=$_.Length;hidden=[bool]($_.Attributes -band [IO.FileAttributes]::Hidden)} })
      return (@{count=$files.Count;files=$files} | ConvertTo-Json -Compress -Depth 5)
    }
    'search_files' {
      $query=[string]$arguments.query
      if ([string]::IsNullOrWhiteSpace($query)) { throw 'Enter a word to search for.' }
      $textExtensions=@('.txt','.md','.csv','.json','.xml','.yml','.yaml','.log','.ini','.conf','.ps1','.sh','.cmd','.bat','.html')
      $found=[Collections.Generic.List[object]]::new()
      foreach ($item in (Get-LabFiles $root)) {
        $nameMatch=$item.Name.IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0
        $contentMatch=$false
        if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $item.Length -le 65536 -and $item.Extension -in $textExtensions) {
          try { $contentMatch=(Get-Content -LiteralPath $item.FullName -Raw -ErrorAction Stop).IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0 } catch {}
        }
        if ($nameMatch -or $contentMatch) {
          $found.Add([pscustomobject]@{path=$item.FullName.Substring($prefix.Length);match=$(if ($nameMatch -and $contentMatch) {'name and content'} elseif ($nameMatch) {'name'} else {'content'});placeholder=[bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)})
          if ($found.Count -ge 100) { break }
        }
      }
      return (@{count=$found.Count;files=@($found)} | ConvertTo-Json -Compress -Depth 5)
    }
    'read_text' {
      $path=Resolve-LabPath ([string]$arguments.path) $true
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
      return (@{count=$plan.Count;moves=@($plan | Select-Object -First 100)} | ConvertTo-Json -Compress -Depth 5)
    }
    default { throw "Unsupported tool: $name" }
  }
}
$tools=@(
  @{type='function';function=@{name='find_files';description='Find files by wildcard name inside the selected lab folder, including hidden files. Maximum 100 results.';parameters=@{type='object';properties=@{pattern=@{type='string';description='Filename wildcard such as *flag*'}};required=@('pattern')}}},
  @{type='function';function=@{name='search_files';description='Search filenames and small local text file contents for a literal word. Cloud placeholders are searchable by filename only.';parameters=@{type='object';properties=@{query=@{type='string';description='Literal word to search for, such as flag'}};required=@('query')}}},
  @{type='function';function=@{name='read_text';description='Read a small text file inside the selected lab folder using a relative path.';parameters=@{type='object';properties=@{path=@{type='string'}};required=@('path')}}},
  @{type='function';function=@{name='plan_screenshot_sort';description='Preview sorting images from a lab subfolder into year-month subfolders. This never moves files.';parameters=@{type='object';properties=@{folder=@{type='string';description='Relative folder such as Screenshots or .'}};required=@('folder')}}}
)
$systemMessage="You are a local lab assistant. You can search and read only inside the selected lab folder. Use tools for file questions; never invent search results. To organize screenshots, call plan_screenshot_sort and describe the preview. Do not claim files were moved. The user can type /apply to approve the pending move plan. Selected lab folder: $root"
$messages=[Collections.Generic.List[object]]::new()
$messages.Add(@{role='system';content=$systemMessage})
$script:pendingPlan=@()
$script:lastFoundFile=$null
$script:lastFoundFiles=@()
$script:seenFiles=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$script:pendingTextFile=$null
Write-Host "Lab Assistant ready. Folder: $root" -ForegroundColor Green
Write-Host 'Type your questions in THIS terminal window. The browser chat does not have file tools.'
Write-Host 'Type /apply to approve the last sort preview, or /exit.'
while ($true) {
  $inputText=Read-Host 'Lab'
  if ($inputText -eq '/exit') { break }
  if ($inputText -eq '/apply') {
    if ($script:pendingTextFile) {
      $draft=$script:pendingTextFile
      Write-Host "Create '$($draft.path)' with the previewed text? Type CREATE to confirm."
      if ((Read-Host 'Confirm') -ne 'CREATE') { Write-Host 'Cancelled.'; continue }
      try {
        $destination=Resolve-LabPath $draft.path
        if (Test-Path -LiteralPath $destination) { throw 'That file already exists.' }
        New-Item -ItemType File -Path $destination -Value $draft.content -ErrorAction Stop | Out-Null
        Write-Host "Created $($draft.path)."
      } catch { Write-Host "Could not create file: $_" -ForegroundColor Red }
      $script:pendingTextFile=$null
      continue
    }
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
  if ($inputText -match '(?i)\b(?:create|make|write)\b.*\b(?:file|essay)\b') {
    $filenameMatch=[regex]::Match($inputText,'(?i)\b([A-Za-z0-9_-]+\.(?:txt|md))\b')
    if (-not $filenameMatch.Success) {
      Write-Host 'What filename and topic should I use? Try: create essay.txt about password safety.'
      continue
    }
    $filename=$filenameMatch.Groups[1].Value
    $topicMatch=[regex]::Match($inputText,'(?i)\babout\s+(.+?)[?.!]*$')
    if (-not $topicMatch.Success) { Write-Host 'What should the file say? Try: create essay.txt about password safety.'; continue }
    $topic=$topicMatch.Groups[1].Value.Trim()
    try {
      $destination=Resolve-LabPath $filename
      if (Test-Path -LiteralPath $destination) { throw 'That file already exists.' }
      $body=@{model='portable-ai';messages=@(@{role='system';content='Write a concise plain-text essay for a classroom lab. Return only the essay text. No markdown.'},@{role='user';content="Write an essay about: $topic"});temperature=0.4;max_tokens=650} | ConvertTo-Json -Depth 10
      $response=Invoke-RestMethod "http://127.0.0.1:$Port/v1/chat/completions" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 180
      $draft=[string]$response.choices[0].message.content
      if ([string]::IsNullOrWhiteSpace($draft)) { throw 'The model returned no text.' }
      $script:pendingTextFile=[pscustomobject]@{path=$filename;content=$draft}
      Write-Host "Preview of $filename`:`n$draft`nType /apply to review and approve creating this file." -ForegroundColor DarkCyan
    } catch { Write-Host "Could not prepare file: $_" -ForegroundColor Red }
    continue
  }
  if ($inputText -match '(?i)\b(?:suspicious|secret|hidden|interesting)\b') {
    $terms=if ($inputText -match '(?i)\bsuspicious\b') { @('flag','secret','password','passw','hack','hidden','private','key','credential','token') } else { @('flag','secret','hidden','private','password','passw','key','credential','token') }
    $matches=@(Get-LabFiles $root | Where-Object { $name=$_.Name; $name -ne 'desktop.ini' -and (($($_.Attributes -band [IO.FileAttributes]::Hidden)) -or @($terms | Where-Object { $name.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0) } | Select-Object -First 100)
    $script:lastFoundFiles=@($matches | ForEach-Object { $_.FullName.Substring($prefix.Length) })
    $script:lastFoundFile=if ($script:lastFoundFiles.Count -eq 1) { $script:lastFoundFiles[0] } else { $null }
    if ($matches.Count -eq 0) { $answer='No filenames or hidden files matched the common clue words. This is only a clue search, not a malware scan.' }
    else { $answer="Possible clues by filename or hidden attribute (not a malware verdict):`n" + (($script:lastFoundFiles | ForEach-Object { [void]$script:seenFiles.Add($_); "- $_" }) -join "`n") }
    Write-Host $answer -ForegroundColor DarkCyan
    continue
  }
  if ($inputText -match '(?i)^\s*(?:can you\s+)?(?:open|read|show)\s+(?:the\s+)?(?:said|found|those|these)\s+files?\s*[?.!]*\s*$') {
    if (-not $script:lastFoundFiles.Count) { Write-Host 'Search for files first so I know which ones you mean.'; continue }
    foreach ($file in ($script:lastFoundFiles | Select-Object -First 10)) {
      try { Write-Host "${file}:`n$(Invoke-LabTool 'read_text' ([pscustomobject]@{path=$file}))" -ForegroundColor DarkCyan }
      catch { Write-Host "Cannot read '$file': $_" -ForegroundColor DarkCyan }
    }
    continue
  }
  if ($inputText -match '(?i)^\s*(?:can you\s+)?open\s+([A-Za-z0-9_-]+)\s+file\s*[?.!]*\s*$') {
    $query=$Matches[1]
    $candidates=@(Get-LabFiles $root | Where-Object { $_.Name.IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0 } | Select-Object -First 11)
    if ($candidates.Count -eq 1) {
      $file=$candidates[0].FullName.Substring($prefix.Length)
      try { Write-Host "${file}:`n$(Invoke-LabTool 'read_text' ([pscustomobject]@{path=$file}))" -ForegroundColor DarkCyan } catch { Write-Host "Cannot read '$file': $_" }
    } elseif ($candidates.Count -eq 0) { Write-Host "No filename contains '$query'." }
    else { Write-Host "Several filenames contain '$query'. Give the full filename." }
    continue
  }
  if ($inputText -match '(?i)^\s*(?:anything else|any others?)\s*[?.!]*\s*$') {
    $other=@(Get-LabFiles $root | Where-Object { -not $script:seenFiles.Contains($_.FullName.Substring($prefix.Length)) } | Select-Object -First 20)
    if ($other.Count -eq 0) { Write-Host 'No other files found in the selected folder.' }
    else { Write-Host ("Other files:`n" + (($other | ForEach-Object { $relative=$_.FullName.Substring($prefix.Length); [void]$script:seenFiles.Add($relative); "- $relative" }) -join "`n")) }
    continue
  }
  if ($inputText -match '(?i)^\s*(?:can you\s+)?(?:open|read|show)(?:\s+me)?\s+it\s*[?.!]*\s*$') {
    if ($script:lastFoundFile) {
      try { $answer="File contents:`n" + (Invoke-LabTool 'read_text' ([pscustomobject]@{path=$script:lastFoundFile})) }
      catch { $answer="Cannot read '$($script:lastFoundFile)': $_" }
    } else { $answer='I do not have a single file to open yet. Search for a file or give its name.' }
    Write-Host $answer -ForegroundColor DarkCyan
    $messages.Add(@{role='user';content=$inputText})
    $messages.Add(@{role='assistant';content=$answer})
    continue
  }
  if ($inputText -match '(?i)\b(?:open|read)\s+(?:the\s+)?(?:file\s+)?["'']?([A-Za-z0-9._\\/-]+\.[A-Za-z0-9]+)') {
    $requestedFile=$Matches[1]
    try { $answer="File contents:`n" + (Invoke-LabTool 'read_text' ([pscustomobject]@{path=$requestedFile})) }
    catch { $answer="Cannot read '$requestedFile': $_" }
    Write-Host $answer -ForegroundColor DarkCyan
    $messages.Add(@{role='user';content=$inputText})
    $messages.Add(@{role='assistant';content=$answer})
    continue
  }
  if ($inputText -match '(?i)\b(?:look(?:ing)?\s+for|find|search|locate|what\s+about)\b.*\b(?:word|called|named)\s*["'']?([A-Za-z0-9._-]+)') {
    $query=$Matches[1]
    try {
      $data=Invoke-LabTool 'search_files' ([pscustomobject]@{query=$query}) | ConvertFrom-Json
      $script:lastFoundFile=if ($data.count -eq 1) { [string]$data.files[0].path } else { $null }
      $script:lastFoundFiles=@($data.files | ForEach-Object { [string]$_.path; [void]$script:seenFiles.Add([string]$_.path) })
      if ($data.count -eq 0) { $answer="No files with '$query' in the name or local text content were found in the selected folder." }
      else { $answer="Found $($data.count) file(s) matching '$query':`n" + (($data.files | ForEach-Object { $note=if ($_.placeholder) {'; cloud placeholder, name only'} else {''}; "- $($_.path) ($($_.match)$note)" }) -join "`n") }
    } catch { $answer="Search failed: $_" }
    Write-Host $answer -ForegroundColor DarkCyan
    $messages.Add(@{role='user';content=$inputText})
    $messages.Add(@{role='assistant';content=$answer})
    continue
  }
  $messages.Add(@{role='user';content=$inputText})
  try {
    for ($round=0; $round -lt 5; $round++) {
      $body=@{model='portable-ai';messages=@($messages);tools=$tools;tool_choice='auto';temperature=0;max_tokens=512} | ConvertTo-Json -Depth 20
      $response=Invoke-RestMethod "http://127.0.0.1:$Port/v1/chat/completions" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 180
      $message=$response.choices[0].message
      if ($message.tool_calls) {
        foreach ($call in $message.tool_calls) {
          try {
            $argsObject=$call.function.arguments | ConvertFrom-Json
            $result=Invoke-LabTool $call.function.name $argsObject
            switch ($call.function.name) {
              'find_files' {
                $data=$result | ConvertFrom-Json
                $script:lastFoundFile=if ($data.count -eq 1) { [string]$data.files[0].path } else { $null }
                $script:lastFoundFiles=@($data.files | ForEach-Object { [string]$_.path; [void]$script:seenFiles.Add([string]$_.path) })
                if ($data.count -eq 0) { $answer='No matching files found in the selected folder.' }
                else { $answer="Found $($data.count) file(s):`n" + (($data.files | ForEach-Object { "- $($_.path)" }) -join "`n") }
              }
              'search_files' {
                $data=$result | ConvertFrom-Json
                $script:lastFoundFile=if ($data.count -eq 1) { [string]$data.files[0].path } else { $null }
                $script:lastFoundFiles=@($data.files | ForEach-Object { [string]$_.path; [void]$script:seenFiles.Add([string]$_.path) })
                if ($data.count -eq 0) { $answer='No matching files found in the selected folder.' }
                else { $answer="Found $($data.count) file(s):`n" + (($data.files | ForEach-Object { "- $($_.path) ($($_.match))" }) -join "`n") }
              }
              'read_text' { $answer="File contents:`n$result" }
              'plan_screenshot_sort' {
                $data=$result | ConvertFrom-Json
                if ($data.count -eq 0) { $answer='No images to organize in that folder.' }
                else { $answer="Preview of $($data.count) move(s):`n" + (($data.moves | ForEach-Object { "- $($_.from) -> $($_.to)" }) -join "`n") + "`nType /apply to review and approve these moves." }
              }
              default { $answer=$result }
            }
          } catch { $answer="Tool error: $_" }
          Write-Host $answer -ForegroundColor DarkCyan
          $messages.Add(@{role='assistant';content=$answer})
        }
        break
      } else {
        if ($inputText -match '(?i)\b(find|search|locate|open|read|organize|sort)\b') { $answer='I could not verify that file request. Try stating the filename or folder more specifically.' }
        else { $answer=$message.content }
        Write-Host $answer; $messages.Add(@{role='assistant';content=$answer}); break
      }
    }
  } catch { Write-Host "Request failed: $_" -ForegroundColor Red }
}
