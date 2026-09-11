#!/usr/bin/env bash
set -euo pipefail

# Seed the sidecar's key file from a secret at runtime, so keys never live in the
# image. Empty is fine: the sidecar then has no targets and the AI features stay
# off until QUORUM_KEYS_TOML is set. project/ is git- and docker-ignored.
mkdir -p project
printf '%s' "${QUORUM_KEYS_TOML:-}" > project/keys.toml
chmod 600 project/keys.toml

# The sidecar, on localhost, in the background. It reads QUORUM_SIDECAR_TOKEN from
# the container environment, the same value the release reads.
( cd sidecar && python3 quorum_sidecar.py --keys ../project/keys.toml --port 4747 ) &

# Hand the container's port to the Phoenix release. bin/server sets PHX_SERVER=true
# and binds 0.0.0.0:$PORT itself. Migrations run inside that same node at boot,
# asked for by the flag below, rather than in a separate bin/migrate node before
# it: one BEAM start instead of two, which takes seconds off a cold start.
export QUORUM_MIGRATE_ON_BOOT=true
exec /app/bin/server
