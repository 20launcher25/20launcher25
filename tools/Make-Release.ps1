<#
  Собирает чистый архив для GitHub Releases: только файлы программы из manifest.json,
  без скиллов, картинок и служебных скриптов (их лаунчер скачивает сам).

    powershell -NoProfile -ExecutionPolicy Bypass -File tools\Make-Release.ps1

  Результат в папке dist:
    ClaudeCodeLauncher.zip   внутри папка ClaudeCodeLauncher-<версия> с Install.cmd
    release-notes.md         текст релиза: что нового и как установить

  Опубликовать (тег v<версия> на ветке main):
    gh release create v<версия> dist\ClaudeCodeLauncher.zip --title "Claude Code Launcher <версия>" --notes-file dist\release-notes.md
#>
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$man = [IO.File]::ReadAllText((Join-Path $Root 'manifest.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$ver = [string]$man.version
$dist = Join-Path $Root 'dist'
if (-not (Test-Path -LiteralPath $dist)) { New-Item -ItemType Directory -Path $dist | Out-Null }

# файлы должны совпадать с манифестом: иначе архив и обновления разойдутся
$sha = [Security.Cryptography.SHA256]::Create()
foreach ($f in $man.files) {
    $p = Join-Path $Root (([string]$f.path) -replace '/', '\')
    if (-not (Test-Path -LiteralPath $p)) { throw "Нет файла $($f.path). Пересоберите манифест: tools\Make-Manifest.ps1" }
    $h = ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($p))) -replace '-', '').ToLowerInvariant()
    if ($h -ne [string]$f.sha256) { throw "Файл $($f.path) не совпадает с manifest.json. Пересоберите манифест: tools\Make-Manifest.ps1" }
}

# zip вручную: имена записей через «/», чтобы архив открывался везде одинаково
$zipPath = Join-Path $dist 'ClaudeCodeLauncher.zip'
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
$folder = "ClaudeCodeLauncher-$ver"
$fs = [IO.File]::Open($zipPath, [IO.FileMode]::CreateNew)
$zip = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in $man.files) {
        $rel = [string]$f.path
        $entry = $zip.CreateEntry("$folder/$rel", [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset](Get-Item -LiteralPath (Join-Path $Root ($rel -replace '/', '\'))).LastWriteTime
        $es = $entry.Open()
        try { $bytes = [IO.File]::ReadAllBytes((Join-Path $Root ($rel -replace '/', '\'))); $es.Write($bytes, 0, $bytes.Length) } finally { $es.Dispose() }
    }
} finally { $zip.Dispose(); $fs.Dispose() }

# текст релиза
$cl = @($man.changelog | Where-Object { [string]$_.version -eq $ver }) | Select-Object -First 1
$ru = if ($cl) { (@($cl.ru) | ForEach-Object { "- $_" }) -join "`n" } else { '' }
$en = if ($cl) { (@($cl.en) | ForEach-Object { "- $_" }) -join "`n" } else { '' }
$notes = @"
## Что нового

$ru

## Установка

1. Скачайте **ClaudeCodeLauncher.zip** ниже, в разделе Assets.
2. Распакуйте архив целиком в любую папку.
3. Дважды щёлкните **Install.cmd**. На рабочем столе появится ярлык «Claude Code Launcher».

Если Windows спросит, запускать ли файл, нажмите «Подробнее», затем «Выполнить в любом случае».
Уже установленный лаунчер обновится сам, скачивать архив заново не нужно.

---

**Қазақша.** Төмендегі **ClaudeCodeLauncher.zip** мұрағатын жүктеп, толығымен ашыңыз да, **Install.cmd** файлын екі рет басыңыз. Орнатылған лаунчер өзі жаңарады.

**English.** Download **ClaudeCodeLauncher.zip** below, unpack all of it and double-click **Install.cmd**. An installed launcher updates itself.

What's new:

$en
"@
[IO.File]::WriteAllText((Join-Path $dist 'release-notes.md'), $notes, (New-Object Text.UTF8Encoding $false))

$size = [math]::Round((Get-Item -LiteralPath $zipPath).Length / 1KB)
Write-Host "dist\ClaudeCodeLauncher.zip: версия $ver, файлов $(@($man.files).Count), $size КБ"
