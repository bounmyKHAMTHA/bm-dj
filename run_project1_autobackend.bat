@echo off
echo ========================================================
echo   Launching BM DJ - Project 1 (Auto-Backend Mode)
echo ========================================================

rem 1. Check if backend is already listening on port 8000
netstat -ano | findstr "LISTENING" | findstr ":8000" >nul
if %errorlevel% neq 0 (
    echo [1/2] Starting Python Backend silently in background...
    start "" /b "%~dp0backend\.venv\Scripts\python.exe" "%~dp0backend\manage.py" runserver 127.0.0.1:8000
    timeout /t 2 /nobreak >nul
) else (
    echo [1/2] Backend is already running on port 8000.
)

echo [2/2] Launching Windows App...
cd /d "%~dp0bm_dj"
flutter run -d windows
pause
