@echo off
setlocal enabledelayedexpansion

for /f "skip=3 delims=" %%a in ('C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -command "& {&Get-WmiObject Win32_service | Where-Object {$_.StartMode -Match 'Auto'} | FT Name -auto}"') do (
echo Services=%%a
)
