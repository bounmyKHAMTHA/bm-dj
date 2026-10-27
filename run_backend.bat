@echo off
echo ========================================================
echo Starting BM DJ Backend Stream Resolver ...
echo Local URL : http://127.0.0.1:8000/
echo Network   : http://0.0.0.0:8000/
echo ========================================================
cd /d "%~dp0backend"
.venv\Scripts\python.exe manage.py runserver 0.0.0.0:8000
pause
