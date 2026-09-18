param(
  [string[]]$Batches = @(),
  [int]$Parallel = 4,
  [int]$BatchTimeoutMin = 30,
  [string]$Bun = ''
)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $Bun) {
  $cand = Join-Path $env:APPDATA 'npm\node_modules\bun\bin\bun.exe'
  if (Test-Path $cand) { $Bun = $cand } else { $Bun = 'bun' }
}
$out = Join-Path $root 'test-results'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$summary = Join-Path $out 'summary.tsv'

# name|patterns(space-separated)|shard
$all = @(
  'kilocode-1|kilocode|1/3',
  'kilocode-2|kilocode|2/3',
  'kilocode-3|kilocode|3/3',
  'cli|cli|',
  'server|server|',
  'tool|tool|',
  'session|session|',
  'plugin-util|plugin util|',
  'mcp-acp|mcp acp|',
  'core-config|project provider config effect|',
  'services|lsp agent permission account skill storage control-plane|',
  'misc|snapshot filesystem share auth v2 suggestion background question ide patch installation image git fixture format bun permission-task event-manifest|'
)

function Stop-Tree([int]$id) {
  $kids = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$id" -ErrorAction SilentlyContinue)
  foreach ($k in $kids) { Stop-Tree ([int]$k.ProcessId) }
  Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
}

function Get-Leftover {
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'bun.exe' -and $_.CommandLine -match 'opencode-test-' }
}

function Clear-Leftovers {
  foreach ($p in (Get-Leftover)) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
}

Clear-Leftovers

$sel = @($all | Where-Object { $Batches.Count -eq 0 -or ($_.Split('|')[0] -in $Batches) })
if ($sel.Count -eq 0) { throw "no batches matched -Batches: $($Batches -join ',')" }

$results = @()
foreach ($spec in $sel) {
  $parts = $spec -split '\|'
  $name = $parts[0]
  $patterns = @($parts[1] -split ' ')
  $shard = $parts[2]

  $log = Join-Path $out ("batch-{0}.log" -f $name)
  $err = Join-Path $out ("batch-{0}.err.log" -f $name)
  Remove-Item -LiteralPath $log, $err -Force -ErrorAction SilentlyContinue

  $argList = @('test', '--parallel', "$Parallel")
  $argList += $patterns
  if ($shard) { $argList += @('--shard', $shard) }

  $t0 = Get-Date
  Write-Host ("[{0}] start: bun {1}" -f $name, ($argList -join ' '))
  $proc = Start-Process -FilePath $Bun -ArgumentList $argList -WorkingDirectory $root -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
  $exited = $proc.WaitForExit($BatchTimeoutMin * 60000)
  if (-not $exited) {
    Write-Host ("[{0}] timeout after {1} min - killing tree {2}" -f $name, $BatchTimeoutMin, $proc.Id)
    Stop-Tree $proc.Id
    $status = 'timeout'
  } else {
    $status = if ($proc.ExitCode -eq 0) { 'pass' } else { 'fail' }
  }
  $dur = [int]((Get-Date) - $t0).TotalSeconds

  $body = ''
  foreach ($f in @($log, $err)) { if (Test-Path $f) { $body += [IO.File]::ReadAllText($f) } }
  $pass = @([regex]::Matches($body, '\(pass\)')).Count
  $fail = @([regex]::Matches($body, '\(fail\)')).Count

  Clear-Leftovers

  $results += [pscustomobject]@{ batch = $name; status = $status; pass = $pass; fail = $fail; duration_s = $dur; log = $log }
  Write-Host ("[{0}] {1}: pass={2} fail={3} {4}s" -f $name, $status, $pass, $fail, $dur)
}

$lines = @('batch`tpass`tfail`tstatus`tduration_s`tlog')
foreach ($r in $results) { $lines += ("{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f $r.batch, $r.pass, $r.fail, $r.status, $r.duration_s, $r.log) }
Set-Content -LiteralPath $summary -Value $lines

Write-Host ''
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
Write-Host "summary: $summary"
