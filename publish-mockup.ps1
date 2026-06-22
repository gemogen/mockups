<#
.SYNOPSIS
  Публикует один HTML-макет в общую веб-галерею gemogen/mockups.

.DESCRIPTION
  Копирует self-contained HTML (и опционально эскиз) в папку <slug>/,
  добавляет или обновляет запись в manifest.json, делает commit + push.
  Живая галерея: https://gemogen.github.io/mockups/

.EXAMPLE
  ./publish-mockup.ps1 -App garage -Name "Гараж" -Icon "🚗" -Screen to `
    -Title "ТО — таймлайн" -Html ".\to.html" -Sketch ".\sketch_to.png" -Status "на согласовании"

.NOTES
  Запускать из корня клона gemogen/mockups (там, где лежит manifest.json).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$App,      # slug приложения, напр. garage
  [Parameter(Mandatory = $true)][string]$Screen,   # id экрана, напр. to
  [Parameter(Mandatory = $true)][string]$Title,    # человеческое название экрана
  [Parameter(Mandatory = $true)][string]$Html,     # путь к self-contained HTML-макету
  [string]$Name,                                   # имя приложения (для новой карточки)
  [string]$Icon = "📱",                            # emoji-иконка (для новой карточки)
  [string]$Sketch,                                 # опционально: путь к PNG-эскизу
  [string]$Status = "на согласовании",             # статус-бейдж
  [switch]$NoPush                                   # собрать локально, не пушить
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$manifestPath = Join-Path $root "manifest.json"

if (-not (Test-Path $manifestPath)) {
  throw "manifest.json не найден в $root — запускай скрипт из корня клона gemogen/mockups."
}
if (-not (Test-Path $Html)) {
  throw "HTML-макет не найден: $Html"
}

# 1. Копируем HTML в <slug>/<screen>.html
$appDir = Join-Path $root $App
New-Item -ItemType Directory -Force $appDir | Out-Null
$htmlRel = "$App/$Screen.html"
$htmlDst = Join-Path $root $htmlRel
Copy-Item $Html $htmlDst -Force
Write-Host "[+] HTML -> $htmlRel"

# 2. Копируем эскиз, если задан
$sketchRel = $null
if ($Sketch) {
  if (-not (Test-Path $Sketch)) { throw "Эскиз не найден: $Sketch" }
  $sketchDir = Join-Path $appDir "sketch"
  New-Item -ItemType Directory -Force $sketchDir | Out-Null
  $ext = [System.IO.Path]::GetExtension($Sketch)
  $sketchRel = "$App/sketch/$Screen$ext"
  Copy-Item $Sketch (Join-Path $root $sketchRel) -Force
  Write-Host "[+] эскиз -> $sketchRel"
}

# 3. Читаем/обновляем manifest.json
$json = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $json.apps) { $json | Add-Member -NotePropertyName apps -NotePropertyValue @() }

$appObj = $json.apps | Where-Object { $_.slug -eq $App } | Select-Object -First 1
if (-not $appObj) {
  if (-not $Name) { $Name = $App }
  $appObj = [pscustomobject]@{ slug = $App; name = $Name; icon = $Icon; screens = @() }
  $json.apps += $appObj
  Write-Host "[+] новая карточка приложения: $Name ($App)"
}

$today = (Get-Date).ToString("yyyy-MM-dd")
$screenObj = $appObj.screens | Where-Object { $_.id -eq $Screen } | Select-Object -First 1
if ($screenObj) {
  $screenObj.title = $Title
  $screenObj.file = $htmlRel
  $screenObj.status = $Status
  $screenObj.updated = $today
  if ($sketchRel) {
    if ($screenObj.PSObject.Properties.Name -contains "sketch") { $screenObj.sketch = $sketchRel }
    else { $screenObj | Add-Member -NotePropertyName sketch -NotePropertyValue $sketchRel }
  }
  Write-Host "[~] обновлён экран: $Title ($Screen)"
} else {
  $new = [ordered]@{ id = $Screen; title = $Title; file = $htmlRel; status = $Status; updated = $today }
  if ($sketchRel) { $new.sketch = $sketchRel }
  $appObj.screens += [pscustomobject]$new
  Write-Host "[+] новый экран: $Title ($Screen)"
}

# 4. Пишем manifest обратно (UTF-8 без BOM — иначе fetch/JSON.parse спотыкается)
$out = $json | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($manifestPath, $out, (New-Object System.Text.UTF8Encoding $false))
Write-Host "[+] manifest.json обновлён"

# 5. Commit + push
if ($NoPush) {
  Write-Host "[i] -NoPush: изменения собраны локально, без отправки."
  return
}
Push-Location $root
try {
  git add -A
  git commit -m "mockup: $App/$Screen — $Title" | Out-Null
  git push
  Write-Host "[OK] опубликовано. Галерея: https://gemogen.github.io/mockups/"
  Write-Host "     (CDN обновляется ~1 мин; в галерее нажми '↻ Обновить')"
} finally {
  Pop-Location
}
