param(
  [string]$Dir = '',
  [string]$Filter = ''
)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $Dir) { $Dir = Join-Path $root 'test-results' }
if (-not (Test-Path $Dir)) { throw "directory not found: $Dir" }

$logs = @(Get-ChildItem -LiteralPath $Dir -File |
  Where-Object { $_.Name -match '^batch-.*\.log$' } |
  Sort-Object Name)
if ($logs.Count -eq 0) { throw "no batch logs found in $Dir" }

$failRe = [regex]'\(fail\)\s+(.+)'
$secRe = [regex]'^(\S+\.test\.ts):$'

$rows = @()
$seen = @{}
foreach ($l in $logs) {
  $batch = $l.BaseName -replace '^batch-', '' -replace '\.err$', ''
  $sec = ''
  foreach ($line in [IO.File]::ReadLines($l.FullName)) {
    if ($secRe.IsMatch($line)) { $sec = $line.TrimEnd(':'); continue }
    $m = $failRe.Match($line)
    if (-not $m.Success) { continue }
    $name = $m.Groups[1].Value.Trim()
    if ($Filter -and $name -notlike $Filter) { continue }
    $key = "{0}`t{1}`t{2}" -f $batch, $sec, $name
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    $rows += [pscustomobject]@{ batch = $batch; sec = $sec; name = $name }
  }
}

if ($rows.Count -eq 0) { Write-Host "no failures found in $Dir"; exit 0 }

$cache = @{}
function Get-Link {
  param([string]$rel, [string]$leaf)
  if (-not $rel) { return '' }
  $ck = "$rel`t$leaf"
  if ($cache.ContainsKey($ck)) { return $cache[$ck] }
  $abs = Join-Path $root $rel
  $link = ''
  if (Test-Path -LiteralPath $abs) {
    $link = $abs
    if ($leaf) {
      $i = 0
      foreach ($t in [IO.File]::ReadLines($abs)) {
        $i++
        if ($t.Contains($leaf)) { $link = "$abs`:$i"; break }
      }
    }
  }
  $cache[$ck] = $link
  return $link
}

$count = @{}
foreach ($r in $rows) { $count[$r.batch] = [int]$count[$r.batch] + 1 }

$cur = ''
foreach ($r in $rows) {
  if ($r.batch -ne $cur) {
    $cur = $r.batch
    Write-Host ''
    Write-Host ("== {0} ({1}) ==" -f $cur, $count[$cur])
  }
  $parts = $r.name -split '\s>\s'
  $leaf = $parts[$parts.Count - 1] -replace '\s*\[\d[\d.]*\s*(ms|s|µs)\]\s*$', ''
  $link = Get-Link $r.sec $leaf
  Write-Host "  $($r.name)"
  if ($link) { Write-Host "      $link" }
}
Write-Host ''
Write-Host ("total: {0} failures across {1} batches" -f $rows.Count, $count.Count)
