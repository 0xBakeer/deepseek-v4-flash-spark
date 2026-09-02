#!/usr/bin/env bash
# Kill the server if available memory drops below WATCHDOG_MIN_AVAIL_GB (default 4).
#
# On a unified-memory board the model weights, the KV pools and the OS page cache all come out
# of the same 128 GB. When available memory reaches zero the machine does not OOM-kill quickly —
# it pages for tens of minutes with the network up and SSH unresponsive. A clean kill beats that.
set -u
min="${WATCHDOG_MIN_AVAIL_GB:-4}"
sleep 30
while pgrep -f "[m]ain.py --config" >/dev/null; do
  avail=$(free -g | awk '/Mem:/ {print $7}')
  if [ "${avail}" -lt "${min}" ]; then
    echo "$(date -Is) watchdog: available memory ${avail} GB < ${min} GB, stopping the server" >&2
    pkill -9 -f "[m]ain.py --config"
    exit 1
  fi
  sleep 3
done
