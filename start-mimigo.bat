@echo off
setlocal EnableExtensions

set "APP_DIR=%~dp0"
set "APP_EXE=%APP_DIR%mimigo.exe"
set "APP_LOG=%APP_DIR%mimigo.log"
set "HOST=127.0.0.1"
set "PORT=18084"
set "PORT_START=18085"
set "PORT_END=18100"
set "APP_URL=http://%HOST%:%PORT%"
set "FOUND_PID="
set "FOUND_PATH="

if not exist "%APP_EXE%" (
  echo Missing "%APP_EXE%".
  pause
  exit /b 1
)

set "MIMIGO_BACKEND_HOST=%HOST%"
set "MIMIGO_DB_PATH=%APP_DIR%mimigo.db"
set "MIMIGO_PAUSE_ON_ERROR=0"

call :prepare_port
set "PORT_RESULT=%ERRORLEVEL%"
if "%PORT_RESULT%"=="2" exit /b 0
if not "%PORT_RESULT%"=="0" exit /b 1
set "MIMIGO_BACKEND_PORT=%PORT%"

:start_new
echo Mimigo is starting.
echo Website:  %APP_URL%
echo Database: %MIMIGO_DB_PATH%
echo Log:      %APP_LOG%
echo.
echo Keep this window open while using Mimigo. Press Ctrl+C to stop.
echo.

start "Mimigo browser opener" powershell -NoProfile -WindowStyle Hidden -Command "Start-Sleep -Seconds 2; Start-Process '%APP_URL%'"
"%APP_EXE%" >> "%APP_LOG%" 2>&1
set "APP_EXIT=%ERRORLEVEL%"

if "%APP_EXIT%"=="0" exit /b 0

echo.
echo Mimigo stopped with exit code %APP_EXIT%.
echo.
if exist "%APP_LOG%" (
  echo Last log output:
  echo ------------------------------------------------------------
  powershell -NoProfile -ExecutionPolicy Bypass -Command "if (Test-Path -LiteralPath '%APP_LOG%') { Get-Content -LiteralPath '%APP_LOG%' -Tail 80 }"
  echo ------------------------------------------------------------
)
echo This window is staying open so the error can be read.
pause
exit /b %APP_EXIT%

:prepare_port
call :find_port_owner
if not defined FOUND_PID exit /b 0
call :handle_existing_mimigo
set "EXISTING_RESULT=%ERRORLEVEL%"
if "%EXISTING_RESULT%"=="0" exit /b 2
if "%EXISTING_RESULT%"=="2" exit /b 0
if "%EXISTING_RESULT%"=="3" exit /b 1
call :choose_available_port
exit /b %ERRORLEVEL%

:handle_existing_mimigo
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $response = Invoke-RestMethod -UseBasicParsing -TimeoutSec 2 '%APP_URL%/api/health'; if ($response.status -eq 'ok') { exit 0 }; exit 1 } catch { exit 1 }"
if errorlevel 1 exit /b 1
call :read_owner_path
if /i "%FOUND_PATH%"=="%APP_EXE%" (
  echo Mimigo is already running at %APP_URL%.
  start "" "%APP_URL%"
  exit /b 0
)
echo Existing Mimigo is running from another package. Stopping it before starting this package.
echo Running PID:  %FOUND_PID%
echo Running EXE:  %FOUND_PATH%
echo This package: %APP_EXE%
echo.
call :stop_existing_mimigo
if errorlevel 1 exit /b 3
exit /b 2

:choose_available_port
call :read_owner_path
echo Port %PORT% is already in use by a non-Mimigo process.
echo Process ID: %FOUND_PID%
if defined FOUND_PATH echo Process EXE: %FOUND_PATH%
echo.
echo Looking for an available port from %PORT_START% to %PORT_END%.
for /l %%P in (%PORT_START%,1,%PORT_END%) do (
  call :port_is_free %%P
  if not errorlevel 1 (
    set "PORT=%%P"
    set "APP_URL=http://%HOST%:%%P"
    echo Using %APP_URL% instead.
    exit /b 0
  )
)
echo No available port found from %PORT_START% to %PORT_END%.
pause
exit /b 1

:port_is_free
set "CHECK_PID="
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /r /c:":%~1 .*LISTENING"') do (
  set "CHECK_PID=%%P"
)
if defined CHECK_PID exit /b 1
exit /b 0

:stop_existing_mimigo
taskkill /pid %FOUND_PID% /t
if errorlevel 1 (
  echo Graceful stop failed. Trying force stop.
  taskkill /pid %FOUND_PID% /t /f
  if errorlevel 1 (
    echo Failed to stop old Mimigo process %FOUND_PID%.
    pause
    exit /b 1
  )
)
call :wait_for_port_release
if not errorlevel 1 exit /b 0
echo Old Mimigo did not release port %PORT% in time. Trying force stop.
taskkill /pid %FOUND_PID% /t /f
if errorlevel 1 (
  echo Failed to force stop old Mimigo process %FOUND_PID%.
  pause
  exit /b 1
)
call :wait_for_port_release
if errorlevel 1 (
  echo Port %PORT% is still in use after stopping process %FOUND_PID%.
  pause
  exit /b 1
)
exit /b 0

:wait_for_port_release
for /l %%I in (1,1,20) do (
  call :find_port_owner
  if not defined FOUND_PID exit /b 0
  timeout /t 1 /nobreak >nul
)
exit /b 1

:find_port_owner
set "FOUND_PID="
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /r /c:":%PORT% .*LISTENING"') do (
  set "FOUND_PID=%%P"
)
exit /b 0

:read_owner_path
set "FOUND_PATH="
if not defined FOUND_PID exit /b 1
for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$process = Get-CimInstance Win32_Process -Filter 'ProcessId=%FOUND_PID%' -ErrorAction SilentlyContinue; if ($process) { [Console]::Write($process.ExecutablePath) }"`) do (
  set "FOUND_PATH=%%P"
)
exit /b 0

:show_port_owner_if_blocked
if not defined FOUND_PID exit /b 0
echo Port %PORT% is already in use, but it did not answer as Mimigo.
echo Process ID: %FOUND_PID%
call :read_owner_path
if defined FOUND_PATH echo Process EXE: %FOUND_PATH%
echo.
echo Close that program or change MIMIGO_BACKEND_PORT, then start Mimigo again.
echo.
tasklist /fi "PID eq %FOUND_PID%"
pause
exit /b 1
