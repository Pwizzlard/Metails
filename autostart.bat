@echo off
set "link=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Metails watcher.cmd"
if exist "%link%" (
    del "%link%"
    echo Metails watcher removed from Startup.
) else (
    > "%link%" echo start "" /min pythonw "%~dp0watch.pyw"
    start "" /min pythonw "%~dp0watch.pyw"
    echo Metails watcher added to Startup and started. Run this again to remove it.
)
pause
