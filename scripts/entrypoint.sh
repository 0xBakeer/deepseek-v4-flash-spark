#!/usr/bin/env bash
# Container entrypoint: make sure the weights are there, arm the memory watchdog, start TabbyAPI.
#
# Environment (all have defaults baked into the image):
#   MODEL_REPO, MODEL_REVISION   the Hugging Face pack and the exact revision to fetch
#   MODEL_NAME                   directory name under MODELS_DIR; also the model id the API reports
#   MODELS_DIR                   where the weights live (mount a volume here)
#   CONFIG                       TabbyAPI config to start with
#   HF_TOKEN                     only needed if your Hugging Face account requires it for downloads
#   WATCHDOG_MIN_AVAIL_GB        kill the server if available memory drops below this (default 4)
set -euo pipefail

echo "deepseek-v4-flash-spark $(cat /app/VERSION 2>/dev/null || echo dev)"

/app/scripts/download-model.sh

# Unified memory has no hard wall between "GPU" and "host" allocations. If something pushes
# available memory towards zero the box does not fail, it thrashes — for a long time. The
# watchdog turns that into a clean exit so the container restarts instead.
/app/scripts/watchdog.sh &

cd /app/tabbyAPI
exec python main.py --config "${CONFIG}"
