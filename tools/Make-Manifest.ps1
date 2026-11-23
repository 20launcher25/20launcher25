<#
  Собирает manifest.json в корне репозитория Claude Code Launcher.
  Запускайте перед каждым коммитом с новой версией:

    powershell -NoProfile -ExecutionPolicy Bypass -File tools\Make-Manifest.ps1

  Что попадает в манифест:
    version    из $AppVersion в launcher.ps1
    changelog  из changelog.json (последние 15 версий)
    files      файлы программы с SHA-256: их лаунчер скачивает при обновлении
    skills     каждая папка skills\<имя>\ с файлом SKILL.md; описание берётся из frontmatter SKILL.md
#>
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

function Sha256([string]$path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($path))) -replace '-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Rel([string]$full) { $full.Substring($Root.Length + 1) -replace '\\', '/' }
function FileEntry([IO.FileInfo]$f) { [ordered]@{ path = (Rel $f.FullName); sha256 = (Sha256 $f.FullName); size = $f.Length } }

# Описание скилла из frontmatter: description: "..." | '...' | текст | > / | (многострочное)
function Skill-Description([string]$file) {
    $lines = [IO.File]::ReadAllLines($file, [Text.Encoding]::UTF8)
    if ($lines.Count -lt 2 -or $lines[0].Trim() -ne '---') { return '' }
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l.Trim() -eq '---') { break }
        if ($l -match '^description:\s*(.*)$') {
            $v = $Matches[1].Trim()
            if ($v -match '^[>|][-+]?$') {
                $parts = @()
                for ($j = $i + 1; $j -lt $lines.Count -and $lines[$j] -match '^\s+\S|^\s*$'; $j++) {
                    if ($lines[$j].Trim() -eq '---') { break }
                    $parts += $lines[$j].Trim()
                }
                return (($parts | Where-Object { $_ }) -join ' ')
            }
            if ($v.Length -ge 2 -and (($v[0] -eq '"' -and $v[-1] -eq '"') -or ($v[0] -eq "'" -and $v[-1] -eq "'"))) {
                $v = $v.Substring(1, $v.Length - 2)
                $v = $v -replace '\\"', '"' -replace "''", "'"
            }
            return $v
        }
    }
    ''
}

$launcher = Join-Path $Root 'launcher.ps1'
$text = [IO.File]::ReadAllText($launcher, [Text.Encoding]::UTF8)
if ($text -notmatch "\`$AppVersion\s*=\s*'([^']+)'") { throw 'В launcher.ps1 не найден $AppVersion' }
$version = $Matches[1]

$changelog = @()
$clFile = Join-Path $Root 'changelog.json'
if (Test-Path -LiteralPath $clFile) {
    $changelog = @([IO.File]::ReadAllText($clFile, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json) | Select-Object -First 15
    if (-not ($changelog | Where-Object { $_.version -eq $version })) {
        Write-Warning "В changelog.json нет записи для версии $version, поэтому «Что нового» будет пустым."
    }
}

# Файлы программы
$files = @()
foreach ($name in @('launcher.ps1', 'Install.cmd', 'Uninstall.cmd', 'Repair.cmd', 'README.txt', 'REPAIR.md', 'POLICY.md', 'POLICY.kk.md', 'POLICY.en.md')) {
    $p = Join-Path $Root $name
    if (Test-Path -LiteralPath $p) { $files += FileEntry (Get-Item -LiteralPath $p) }
}
foreach ($dir in @('usage-mod', 'limits-bar')) {
    $p = Join-Path $Root $dir
    if (Test-Path -LiteralPath $p) {
        foreach ($f in (Get-ChildItem -LiteralPath $p -Recurse -File | Sort-Object FullName)) { $files += FileEntry $f }
    }
}

# Скиллы
$skills = @()
$skRoot = Join-Path $Root 'skills'
if (Test-Path -LiteralPath $skRoot) {
    foreach ($d in (Get-ChildItem -LiteralPath $skRoot -Directory | Sort-Object Name)) {
        $md = Join-Path $d.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $md)) { continue }
        if ($d.Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { Write-Warning "Пропущен скилл с недопустимым именем папки: $($d.Name)"; continue }
        $sf = @(Get-ChildItem -LiteralPath $d.FullName -Recurse -File | Sort-Object FullName | ForEach-Object { FileEntry $_ })
        # ревизия: хеш от путей и хешей всех файлов, меняется при любой правке скилла
        $sig = ($sf | ForEach-Object { "$($_.path)=$($_.sha256)" }) -join "`n"
        $sha = [Security.Cryptography.SHA256]::Create()
        $rev = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($sig))) -replace '-', '').Substring(0, 12).ToLowerInvariant()
        $sha.Dispose()
        $skills += [ordered]@{ name = $d.Name; description = (Skill-Description $md); rev = $rev; files = $sf }
    }
}

$manifest = [ordered]@{
    name      = 'Claude Code Launcher'
    version   = $version
    date      = (Get-Date).ToString('yyyy-MM-dd')
    changelog = @($changelog)
    files     = @($files)
    skills    = @($skills)
}
$json = $manifest | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText((Join-Path $Root 'manifest.json'), $json, (New-Object Text.UTF8Encoding $false))
Write-Host "manifest.json: версия $version, файлов $($files.Count), скиллов $($skills.Count)"
