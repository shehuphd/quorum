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

# PostgreSQL. If it's installed but not running, start it, so a fresh clone
# doesn't stop at a prerequisite the machine already has. Only ever starts a
# server the user has already set up, and never with sudo: where a privileged
# service manager is the only route, the command is printed instead of run.
PGAPP_BIN="/Applications/Postgres.app/Contents/Versions/latest/bin"

# Prefer whatever is on PATH, and fall back to Postgres.app's own copy, which is
# there on a Mac where the app was installed but its bin directory never was.
PG_ISREADY="$(command -v pg_isready 2>/dev/null || true)"
[ -n "$PG_ISREADY" ] || { [ -x "$PGAPP_BIN/pg_isready" ] && PG_ISREADY="$PGAPP_BIN/pg_isready"; }

postgres_ready() { [ -n "$PG_ISREADY" ] && "$PG_ISREADY" -q >/dev/null 2>&1; }

wait_for_postgres() {
  local tries="${1:-20}"
  while [ "$tries" -gt 0 ]; do
    postgres_ready && return 0
    sleep 1
    tries=$((tries - 1))
  done
  return 1
}

# Postgres.app keeps one data directory per major version, each with the version
# in a PG_VERSION file, under a path with a space in it. Each data directory is paired with the binary of that
# same version rather than whatever is first on PATH, so the two can't disagree
# and refuse to start. Newest version first.
start_postgres_app() {
  [ -d "/Applications/Postgres.app/Contents/Versions" ] || return 1

  local data version pg_ctl
  while IFS= read -r data; do
    [ -f "$data/PG_VERSION" ] || continue
    version="$(cat "$data/PG_VERSION")"
    pg_ctl="/Applications/Postgres.app/Contents/Versions/$version/bin/pg_ctl"
    [ -x "$pg_ctl" ] || continue

    say "PostgreSQL isn't running. Starting Postgres.app's server (PostgreSQL $version)."
    "$pg_ctl" -D "$data" -l "$data/quorum-launcher.log" start >/dev/null 2>&1
    wait_for_postgres 20 && return 0
  done < <(printf '%s\n' "$HOME/Library/Application Support/Postgres"/var-* | sort -rV)

  return 1
}

start_postgres_brew() {
  command -v brew >/dev/null 2>&1 || return 1

  local formula
  formula="$(brew services list 2>/dev/null | awk '$1 ~ /^postgresql/ {print $1; exit}')"
  [ -n "$formula" ] || return 1

  say "PostgreSQL isn't running. Starting it with brew services ($formula)."
  brew services start "$formula" >/dev/null 2>&1
  wait_for_postgres 20
}

# A cluster the user runs themselves, named by PGDATA.
start_postgres_pgdata() {
  [ -n "${PGDATA:-}" ] || return 1
  [ -f "$PGDATA/PG_VERSION" ] || return 1
  command -v pg_ctl >/dev/null 2>&1 || return 1

  say "PostgreSQL isn't running. Starting the cluster at \$PGDATA."
  pg_ctl -D "$PGDATA" -l "$PGDATA/quorum-launcher.log" start >/dev/null 2>&1
  wait_for_postgres 20
}

if [ -n "$PG_ISREADY" ]; then
  postgres_ready ||
    start_postgres_app ||
    start_postgres_brew ||
    start_postgres_pgdata ||
    true

  postgres_ready || die "PostgreSQL isn't accepting connections on localhost:5432, and starting it here didn't work.
Start it yourself, then run this again:
  Postgres.app  click the elephant in the menu bar, then Start
  Homebrew      brew services start postgresql
  Linux         sudo systemctl start postgresql
If Postgres.app reports a trust-dialog error, restart its server from the menu bar."
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
