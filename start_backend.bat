@echo off
cd /d "%~dp0backend"
python -m uvicorn fastapi_app:app --reload --host 0.0.0.0 --port 8000
pause
