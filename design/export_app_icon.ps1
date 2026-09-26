# Renders design/app_icon.html to the PNGs the app's icon pipeline consumes.
#
#   design/app_icon.html      single source of truth (vector SVG + previews)
#   assets/icon/app_icon.png  Android legacy + every web size, via flutter_launcher_icons
#   assets/icon/app_icon_foreground.png
#                             Android adaptive foreground, via flutter_launcher_icons
#   windows/runner/resources/app_icon.ico
#   installer/app_icon.ico
#
# Run from the repository root:
#   pwsh -File design/export_app_icon.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$chrome = @(
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $chrome) { throw 'Chrome not found; it is what rasterises the SVG.' }

$page = 'file:///' + ($root.Replace('\', '/')) + '/design/app_icon.html'
$staging = Join-Path $root '.build\icon'
New-Item -ItemType Directory -Force -Path $staging | Out-Null

function Render([string]$mode, [int]$size, [string]$name) {
  $out = Join-Path $staging $name
  & $chrome --headless=new --disable-gpu --hide-scrollbars --no-sandbox `
    --force-device-scale-factor=1 --default-background-color=00000000 `
    --window-size="$size,$size" --screenshot="$out" "$page#$mode" | Out-Null
  if (-not (Test-Path $out)) { throw "render failed: $mode @ $size" }
  "$name  $((Get-Item $out).Length) B"
}

"--- rasterising ---"
Render 'full'    1024 'app_icon.png'
Render 'fg'      1024 'app_icon_foreground.png'
Render 'android'  512 'plate_square.png'
Render 'full'     512 'Icon-512.png'
Render 'full'     192 'Icon-192.png'
Render 'full'     1024 'maskable.png'

"--- installing ---"
Copy-Item (Join-Path $staging 'app_icon.png')            'assets\icon\app_icon.png' -Force
Copy-Item (Join-Path $staging 'app_icon_foreground.png') 'assets\icon\app_icon_foreground.png' -Force
Copy-Item (Join-Path $staging 'Icon-512.png')            'web\icons\Icon-512.png' -Force
Copy-Item (Join-Path $staging 'Icon-192.png')            'web\icons\Icon-192.png' -Force
Copy-Item (Join-Path $staging 'maskable.png')            'web\icons\Icon-maskable-512.png' -Force

# ---- .ico for Windows and the installer -------------------------------
# Sizes follow what Windows actually asks for: 16 in the taskbar, 32 in
# Alt-Tab, 48/64 in Explorer's larger views, 256 for the app tile.
python -c @"
from PIL import Image
import sys, pathlib
src, *dests = sys.argv[1:]
img = Image.open(src).convert('RGBA')
for d in dests:
    img.save(d, format='ICO',
             sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
    print('wrote', d)
"@ (Join-Path $staging 'app_icon.png') 'windows\runner\resources\app_icon.ico' 'installer\app_icon.ico'

"--- done ---"
"Next: flutter pub run flutter_launcher_icons   (regenerates Android mipmaps)"
