#!/usr/bin/env bash
# DeepSeek V4 Flash on a DGX Spark — one entry point for everything.
#
#   ./run.sh setup     pull the image (or build it with BUILD=1) and download the weights (~92 GB)
#   ./run.sh serve     start the server on http://127.0.0.1:8000/v1 (detached)
#   ./run.sh logs      follow the server log
#   ./run.sh stop      stop it
#   ./run.sh bench     measure time-to-first-token and streamed decode rate
#   ./run.sh shell     a shell inside the running container
#
# Overridable by environment: PORT (8000), MODELS_DIR (./models), RECIPE_VERSION (pinned),
# BUILD=1 (build the image here instead of pulling it), HF_TOKEN.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
export RECIPE_VERSION="${RECIPE_VERSION:-$(cat VERSION)}"
export PORT="${PORT:-8000}"
export MODELS_DIR="${MODELS_DIR:-$HERE/models}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

need() {
  command -v docker >/dev/null || die "docker not found"
  docker compose version >/dev/null 2>&1 || die "docker compose (v2) not found"
  [ "$(uname -m)" = "aarch64" ] || die "this recipe is for the DGX Spark (aarch64); this machine is $(uname -m)"
  docker info 2>/dev/null | grep -qi nvidia || \
    log "warning: no NVIDIA runtime visible to docker — install nvidia-container-toolkit if 'serve' fails"
}

case "${1:-}" in
  setup)
    need
    mkdir -p "$MODELS_DIR"
    if [ "${BUILD:-0}" = "1" ]; then
      log "building the image on this machine (engine compile: ~20 min)"
      docker compose build
    else
      log "pulling ghcr.io/0xbakeer/deepseek-v4-flash-spark:$RECIPE_VERSION"
      docker compose pull
    fi
    free_gb=$(df -BG --output=avail "$MODELS_DIR" | tail -1 | tr -dc '0-9')
    [ "${free_gb:-0}" -lt 100 ] && log "warning: only ${free_gb} GB free under $MODELS_DIR; the weights are 92 GB"
    log "downloading the weights into $MODELS_DIR (92 GB, resumable — re-run if it stops)"
    docker compose run --rm --no-deps --entrypoint /app/scripts/download-model.sh deepseek
    log "done. next: ./run.sh serve"
    ;;
  serve)
    need
    log "starting (version $RECIPE_VERSION) — first token is ~40 s away on a warm disk, minutes on a cold one"
    docker compose up -d
    log "waiting for http://127.0.0.1:$PORT/health"
    for _ in $(seq 1 360); do
      curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && { log "up: http://127.0.0.1:$PORT/v1"; exit 0; }
      sleep 5
    done
    die "not healthy after 30 minutes — ./run.sh logs"
    ;;
  logs)  docker compose logs -f --tail 200 ;;
  stop)  docker compose down ;;
  shell) docker compose exec deepseek bash ;;
  bench) shift; exec python3 bench/bench.py --api "http://127.0.0.1:$PORT" "$@" ;;
  ""|-h|--help|help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command: $1 (try ./run.sh help)" ;;
esac
