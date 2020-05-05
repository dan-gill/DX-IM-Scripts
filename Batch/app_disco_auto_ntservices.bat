@echo off
set "startmode=auto"
for /f "skip=1 delims=" %%a in ('wmic service where "startmode='%startmode%'" get name ^| findstr /r /v "^$" ') do (
   echo Services=%%a
)
