@echo off
rem Quorum launcher for Windows. Sets up the database and starts the app.
cd /d "%~dp0"

where mix >nul 2>nul
if errorlevel 1 (
  echo Elixir ^(with mix^) isn't installed. Install it from https://elixir-lang.org/install.html, then run this again.
  exit /b 1
)

call mix deps.get || exit /b 1
call mix ash.setup || exit /b 1

set PORT=4000
start "" "http://localhost:%PORT%"
mix phx.server
