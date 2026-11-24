# Закреплённый Godot для локальных проверок (#255): то же, что шаг CI «Закреплённый Godot и export templates».
# Один раз качает Godot 4.7.2 и export templates в dist/godot/engine/<версия>/ (в Git не попадает),
# включает самодостаточный режим (_sc_) и кладёт шаблоны рядом, чтобы экспорт работал с изолированным APPDATA.
# Повторный запуск ничего не качает. Печатает путь к консольному exe последней строкой.
param([string]$Version = '4.7.2')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # без этого Invoke-WebRequest в Windows PowerShell 5.1 качает в разы медленнее
$workspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$root = Join-Path $workspaceRoot "dist/godot/engine/$Version"
$exe = Join-Path $root "Godot_v$Version-stable_win64_console.exe"
$templates = Join-Path $root "editor_data/export_templates/$Version.stable"
$base = "https://github.com/godotengine/godot/releases/download/$Version-stable"
New-Item -ItemType Directory -Force $root | Out-Null

if (-not (Test-Path -LiteralPath $exe)) {
    Write-Host "Скачиваю Godot $Version"
    $zip = Join-Path $root 'godot.zip'
    Invoke-WebRequest "$base/Godot_v$Version-stable_win64.exe.zip" -OutFile $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $root -Force
    Remove-Item -LiteralPath $zip
    if (-not (Test-Path -LiteralPath $exe)) { throw "В архиве нет $exe" }
}
$sc = Join-Path $root '_sc_'
if (-not (Test-Path -LiteralPath $sc)) { New-Item -ItemType File $sc | Out-Null }

if (-not (Test-Path -LiteralPath (Join-Path $templates 'windows_release_x86_64.exe'))) {
    Write-Host "Скачиваю export templates $Version (около 1 ГБ, один раз)"
    $tpz = Join-Path $root 'templates.zip'  # Expand-Archive в 5.1 принимает только .zip
    $unpacked = Join-Path $root 'templates-unpacked'
    Invoke-WebRequest "$base/Godot_v$Version-stable_export_templates.tpz" -OutFile $tpz
    Expand-Archive -LiteralPath $tpz -DestinationPath $unpacked -Force
    New-Item -ItemType Directory -Force $templates | Out-Null
    Copy-Item (Join-Path $unpacked 'templates/*') $templates -Recurse -Force
    Remove-Item -LiteralPath $tpz
    Remove-Item -LiteralPath $unpacked -Recurse -Force
    if (-not (Test-Path -LiteralPath (Join-Path $templates 'windows_release_x86_64.exe'))) { throw "Неполные export templates: $templates" }
}
Write-Host "Godot $Version готов (только в dist/, в Git не идёт)"
Write-Output $exe
