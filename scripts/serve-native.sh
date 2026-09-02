#!/usr/bin/env bash
# Start the server from a native (non-Docker) install made with docs/build-from-source.md.
#
#   ROOT=~/deepseek-v4-flash-spark-native ./scripts/serve-native.sh [config.yml]
set -euo pipefail
ROOT="${ROOT:-$HOME/deepseek-v4-flash-spark-native}"
CONFIG="${1:-${CONFIG:-$ROOT/config.yml}}"
export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
export PATH="$CUDA_HOME/bin:$PATH"
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
export EXL3_NO_RLP=1
cd "$ROOT/tabbyAPI"
exec "$ROOT/venv/bin/python" main.py --config "$CONFIG"
