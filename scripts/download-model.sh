#!/usr/bin/env bash
# Fetch the weights if they are not already complete. Safe to re-run; the Hugging Face client
# resumes partial shards and skips finished ones.
set -euo pipefail

: "${MODEL_REPO:=anoane/DeepSeek-V4-Flash-0731-exl3-2.54bpw}"
: "${MODEL_REVISION:=91cf8b7e3cde8833c291bd513590d3fced5e566f}"
: "${MODEL_NAME:=deepseek-v4-flash-0731}"
: "${MODELS_DIR:=/models}"

dir="${MODELS_DIR}/${MODEL_NAME}"
mkdir -p "${dir}"

complete() {
  [ -f "${dir}/model.safetensors.index.json" ] || return 1
  # every shard the index names must exist; a partial download leaves .incomplete files instead
  python3 - "${dir}" <<'PY'
import json, os, sys
d = sys.argv[1]
idx = json.load(open(os.path.join(d, "model.safetensors.index.json")))
shards = sorted(set(idx["weight_map"].values()))
missing = [s for s in shards if not os.path.isfile(os.path.join(d, s))]
sys.exit(1 if missing else 0)
PY
}

if complete; then
  echo "weights present in ${dir}"
  exit 0
fi

free_gb=$(df -BG --output=avail "${MODELS_DIR}" | tail -1 | tr -dc '0-9')
if [ "${free_gb:-0}" -lt 100 ]; then
  echo "WARNING: only ${free_gb} GB free under ${MODELS_DIR}; the pack is 92 GB." >&2
fi

echo "fetching ${MODEL_REPO}@${MODEL_REVISION} into ${dir} (92 GB, resumable)"
hf download "${MODEL_REPO}" --revision "${MODEL_REVISION}" --local-dir "${dir}" --max-workers 4

complete || { echo "download finished but shards are missing — re-run to resume" >&2; exit 1; }
echo "weights complete"
