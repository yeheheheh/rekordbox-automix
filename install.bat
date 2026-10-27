@echo off
setlocal
cd /d "%~dp0"
echo.
echo  rekordbox-automix installer
echo  ==========================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install\install.ps1" %*
set "CODE=%ERRORLEVEL%"
echo.
if not "%CODE%"=="0" (
    echo Installation failed with exit code %CODE%.
    echo Log: %LOCALAPPDATA%\djcore\install.log
    pause
    exit /b %CODE%
)
echo Installation finished.
echo.
echo Start the API:        %LOCALAPPDATA%\djcore\start-api.bat
echo Rekordbox status:     %LOCALAPPDATA%\djcore\rekordbox-status.bat
echo Local demo render:    %LOCALAPPDATA%\djcore\local-demo.bat
echo MCP config:           %LOCALAPPDATA%\djcore\mcp-config.json
echo.
pause
