#!/usr/bin/env bash
# Double-click a few minutes before a demo to wake the live app.
#
# The app scales to zero when idle, so the first request after a quiet spell
# takes a cold start. This sends that first request now, off-camera, so the demo
# opens on a warm app. It stays warm while there's traffic and for a short while
# after, so two or three minutes ahead is enough.

URL="https://quorum.orangecoast-00205bd0.uksouth.azurecontainerapps.io/"

cd "$(dirname "$0")"

echo "Waking Quorum…"
echo "$URL"
echo

start=$(date +%s)
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 90 "$URL")
elapsed=$(( $(date +%s) - start ))

echo
if [ "$code" = "200" ]; then
  echo "Awake. Answered 200 in ${elapsed}s."
  echo "Open the demo within a couple of minutes and it'll be warm."
else
  echo "Got HTTP $code after ${elapsed}s."
  echo "Try again in a moment; if it keeps failing, check the app in Azure."
fi

echo
echo "You can close this window."
