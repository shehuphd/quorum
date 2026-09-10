#!/usr/bin/env bash
# Start the AI sidecar beside Quorum. Generates a session token if none is set,
# and prints it so the app can be started with the same one.
set -euo pipefail
cd "$(dirname "$0")"

command -v python3 >/dev/null 2>&1 || {
  echo "Python 3 isn't installed. Install it, then run this again." >&2
  exit 1
}

python3 -c "import keycall" 2>/dev/null || {
  echo "Installing the sidecar's requirements."
  python3 -m pip install --quiet -r requirements.txt
}

if [ -z "${QUORUM_SIDECAR_TOKEN:-}" ]; then
  QUORUM_SIDECAR_TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
  export QUORUM_SIDECAR_TOKEN
  echo "QUORUM_SIDECAR_TOKEN=$QUORUM_SIDECAR_TOKEN"
  echo "Start Quorum with that same variable set, or the app can't reach this."
fi

exec python3 quorum_sidecar.py --keys ../project/keys.toml "$@"
