@echo off
schtasks /query /tn "Metails records" >nul 2>&1
if %errorlevel%==0 (
    schtasks /delete /tn "Metails records" /f >nul
    echo Metails records task removed. Your records stay as they are.
) else (
    schtasks /create /tn "Metails records" /sc hourly /tr "pythonw \"%~dp0records.py\"" /f >nul
    schtasks /run /tn "Metails records" >nul
    echo Metails will now import boss kill curves from your combat logs once an hour. Run this again to stop.
)
pause
