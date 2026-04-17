@echo off
setlocal

set ICON_DIR=%~dp0..\assets\icon

"L:\Program Files\Inkscape\bin\inkscape.exe" --export-type=png --export-background-opacity=0 -w 256 "%ICON_DIR%\app_icon.svg"
dart run flutter_launcher_icons -f .\flutter_launcher_icons.yaml
echo Done.
