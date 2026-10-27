@echo off
echo ========================================================
echo   Launching BM DJ - Project 1 (Auto-Backend Mode)
echo   (Backend will start silently in background if needed)
echo ========================================================
cd /d "%~dp0bm_dj"
flutter run -d windows
pause
