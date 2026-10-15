@echo off
rem PlayBridge installer: double-click this file. No administrator rights needed.
rem Run it again later to change the player, link NAS folders, update or uninstall.
rem https://github.com/Damocles-fr/MPC-JF
setlocal
set "PB_DIR=%~dp0"
if not exist "%PB_DIR%PlayBridge-Core.ps1" goto :notextracted
if not exist "%PB_DIR%PlayBridge.ps1" goto :notextracted
rem leave the PlayBridge folder, so that it can be updated or deleted while the setup runs
cd /d "%TEMP%"
echo.
echo   PlayBridge Setup is opening, please wait...
echo   This window closes by itself.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%PB_DIR%PlayBridge-Core.ps1" %* || (echo. & echo   PlayBridge Setup stopped with an error, see the message above. & echo   Help: https://github.com/Damocles-fr/MPC-JF & echo. & pause) & exit /b
exit /b

:notextracted
echo.
echo   Please extract PlayBridge.zip first:
echo   right-click the .zip file, "Extract All...", then double-click Install.cmd
echo   in the extracted folder.
echo.
pause
exit /b 1
