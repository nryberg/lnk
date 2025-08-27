#!/usr/bin/env bash
set -euo pipefail

# Defaults; can be overridden by env
TS_STATE_DIR="${TS_STATE_DIR:-/var/lib/tailscale}"
TS_HOSTNAME="${TS_HOSTNAME:-myapp}"
TS_EXTRA_ARGS="${TS_EXTRA_ARGS:-}"
TS_TUN_MODE="${TS_TUN_MODE:-tun}"   # "tun" or "userspace-networking"
APP_USER="${APP_USER:-appuser}"
APP_GROUP="${APP_GROUP:-appuser}"

mkdir -p "${TS_STATE_DIR}"

# Determine TUN flag
if [ "${TS_TUN_MODE}" = "userspace-networking" ]; then
  TUN_FLAG="--tun=userspace-networking"
else
  TUN_FLAG=""
fi

# Start tailscaled in the background as root (needs privileges)
/usr/local/bin/tailscaled --state="${TS_STATE_DIR}/tailscaled.state" ${TUN_FLAG} &
TS_PID=$!

# Give tailscaled a moment to initialize
sleep 2

# Bring Tailscale up (if already logged in, this will be a no-op and succeed)
# Use --authkey via env at runtime (recommended). If not provided, this will try to reuse prior state.
if ! /usr/local/bin/tailscale up --hostname="${TS_HOSTNAME}" ${TS_EXTRA_ARGS}; then
  echo "tailscale up failed; if this is a first run, ensure TS_AUTHKEY is provided or enroll interactively."
fi

# Optional: print brief status for logs
/usr/local/bin/tailscale status || true
/usr/local/bin/tailscale ip -4 || true

# Drop to unprivileged user for the app
if [ "$(id -u)" -eq 0 ]; then
  exec su-exec "${APP_USER}:${APP_GROUP}" "$@"
else
  exec "$@"
fi
