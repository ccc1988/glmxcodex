@echo off
echo Starting Codex Multi-Backend Proxy...
set PROXY_PORT=18765
python "%~dp0proxy.py"
pause
