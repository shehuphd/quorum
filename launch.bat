@echo off
rem Quorum launcher for Windows. Starts PostgreSQL if it isn't running, sets up
rem the database, and starts the app.
setlocal
cd /d "%~dp0"

where mix >nul 2>nul
if errorlevel 1 (
  echo Elixir ^(with mix^) isn't installed. Install it from https://elixir-lang.org/install.html, then run this again.
  exit /b 1
)

rem PostgreSQL. Only attempted when pg_isready is on PATH to say whether it's
rem needed; the service start is allowed to fail without administrator
rem rights, and the message below covers that case.
where pg_isready >nul 2>nul
if errorlevel 1 (
  echo Note: 'pg_isready' not found; skipping the database check. If setup fails, make sure PostgreSQL is installed and running.
  goto :deps
)

pg_isready -q >nul 2>nul
if not errorlevel 1 goto :deps

echo PostgreSQL isn't running. Trying to start it.

rem A cluster the user runs themselves, named by PGDATA.
if defined PGDATA (
  if exist "%PGDATA%\PG_VERSION" pg_ctl -D "%PGDATA%" -l "%PGDATA%\quorum-launcher.log" start >nul 2>nul
)

rem The installer's Windows service, whatever version it registered as.
for /f "tokens=2 delims=: " %%s in ('sc query type^= service state^= all ^| findstr /I "SERVICE_NAME" ^| findstr /I "postgresql"') do (
  net start "%%s" >nul 2>nul
)

rem Give it a few seconds to come up.
for /l %%i in (1,1,10) do (
  pg_isready -q >nul 2>nul
  if not errorlevel 1 goto :deps
  timeout /t 1 /nobreak >nul
)

echo PostgreSQL isn't accepting connections on localhost:5432, and starting it here didn't work.
echo Start it yourself, then run this again:
echo   Services      start the postgresql service ^(needs administrator rights^)
echo   Command line  pg_ctl -D "path\to\data" start
exit /b 1

:deps
call mix deps.get || exit /b 1
call mix ash.setup || exit /b 1

set PORT=4000
start "" "http://localhost:%PORT%"
mix phx.server
