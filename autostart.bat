@echo off
set "link=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Metails watcher.cmd"
if exist "%link%" (
    del "%link%"
    echo Metails watcher removed from Startup. Close any running pythonw watcher yourself if you like.
) else (
    > "%link%" echo start "" /min pythonw "%~dp0watcher.pyw"
    start "" /min pythonw "%~dp0watcher.pyw"
    echo Metails watcher started and added to Startup. It imports your boss kill curves right after each kill. Run this again to remove it.
)
pause
