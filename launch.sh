#!/usr/bin/env bash
# Quorum launcher. Takes a fresh clone to a running app in one command: it kills
# a stale instance of this project's server, checks prerequisites with plain
# messages, sets up the database, picks a free port, and opens the browser.
set -uo pipefail

cd "$(dirname "$0")"
PROJECT_DIR="$(pwd -P)"
DEFAULT_PORT=4000
MAX_PORT_TRIES=20

say() { printf '%s\n' "$*"; }
die() { say "$*"; exit 1; }

# Kill any already-running server for THIS project, never reuse it. Matched by the
# process's own working directory, so another Phoenix app is left untouched.
kill_stale() {
  local signal="$1" pid cwd
  for pid in $(pgrep -f "phx.server" 2>/dev/null || true); do
    cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1 || true)"
    [ "$cwd" = "$PROJECT_DIR" ] && kill "$signal" "$pid" 2>/dev/null || true
  done
}
kill_stale -TERM
sleep 1
kill_stale -KILL

command -v mix >/dev/null 2>&1 || die \
  "Elixir (with mix) isn't installed. Install it from https://elixir-lang.org/install.html, then run this again."

if command -v pg_isready >/dev/null 2>&1; then
  pg_isready -q >/dev/null 2>&1 || die \
    "PostgreSQL isn't accepting connections on localhost:5432. Start it (Postgres.app from the menu bar, or 'pg_ctl start'), then run this again. If Postgres.app reports a trust-dialog error, restart its server from the menu bar."
else
  say "Note: 'pg_isready' not found; skipping the database check. If setup fails, make sure PostgreSQL is installed and running."
fi

mix deps.get || die "Fetching dependencies failed. See the output above."
mix ash.setup || die "Database setup failed. Check that PostgreSQL is running and reachable."

# Pick a free port, skipping the ports Chromium refuses to open.
BLOCKED="6000 6566 6665 6666 6667 6668 6669 6697"
port_in_use() { lsof -ti ":$1" -sTCP:LISTEN >/dev/null 2>&1; }
is_blocked() { case " $BLOCKED " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

PORT="$DEFAULT_PORT"
tries=0
while { port_in_use "$PORT" || is_blocked "$PORT"; } && [ "$tries" -lt "$MAX_PORT_TRIES" ]; do
  PORT=$((PORT + 1))
  tries=$((tries + 1))
done
port_in_use "$PORT" && die "Couldn't find a free port near $DEFAULT_PORT. Close whatever is using it and retry."

URL="http://localhost:$PORT"
say "Starting Quorum on $URL"

# Open the browser once the server answers, without blocking the server itself.
(
  for _ in $(seq 1 60); do
    curl -s -o /dev/null "$URL" && break
    sleep 1
  done
  if command -v open >/dev/null 2>&1; then
    open "$URL"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL"
  fi
) >/dev/null 2>&1 &

PORT="$PORT" exec mix phx.server
