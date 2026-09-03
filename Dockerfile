# DeepSeek V4 Flash on one DGX Spark — serving image.
#
# Everything the server needs is built here, pinned to exact commits: PyTorch cu130, the
# exllamav3 fork that loads this pack, TabbyAPI, the chat template, the sampling preset and
# the serving configuration. The weights are NOT in the image; the entrypoint fetches them
# into the /models volume on first start (92 GB, resumable).
#
# The image is aarch64-only on purpose: the engine is compiled for the GB10 (sm_121) and the
# CPU-side kernels that exist upstream are x86-only, so this build carries the arm64 port
# in patches/. Build it on the Spark itself:
#
#   docker build -t deepseek-v4-flash-spark .
#
# The engine compile is the slow part (about 20 minutes on the Spark's 20 cores).
FROM nvidia/cuda:13.0.2-devel-ubuntu24.04

ARG EXL3_REPO=https://github.com/anoane/exllamav3-anemone.git
ARG EXL3_SHA=c6d2e3eea40dcd15947f55974bde3555a550a157
ARG TABBY_REPO=https://github.com/theroyallab/tabbyAPI.git
ARG TABBY_SHA=4a4f9f44820303593844f092d424bb7506008733
ARG TORCH_VERSION=2.11.0
ARG RECIPE_VERSION=0.1.1
ARG MAX_JOBS=16

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    CUDA_HOME=/usr/local/cuda \
    PATH=/app/venv/bin:/usr/local/cuda/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-venv python3-dev git ca-certificates curl ninja-build procps \
    && rm -rf /var/lib/apt/lists/* \
    && git config --global http.version HTTP/1.1

RUN python3 -m venv /app/venv \
    && pip install --upgrade pip wheel setuptools ninja

# PyTorch with CUDA 13.0 — the only wheel index that has an aarch64 build for it.
RUN pip install "torch==${TORCH_VERSION}+cu130" --index-url https://download.pytorch.org/whl/cu130

# The engine. anoane/exllamav3-anemone is the exllamav3 fork that understands this pack's
# per-layer bit allocation and ships the DeepSeek V4 MTP draft path. The patch is the aarch64
# port: it drops the x86-only CPU kernels from the build and stubs their symbols.
COPY patches/exllamav3-anemone-aarch64.patch /app/patches/
RUN git clone "${EXL3_REPO}" /app/exllamav3-anemone \
    && cd /app/exllamav3-anemone \
    && git checkout -q "${EXL3_SHA}" \
    && git apply /app/patches/exllamav3-anemone-aarch64.patch

# sm_121 is the GB10. 12.0 is included so the same image also runs on desktop Blackwell.
ENV TORCH_CUDA_ARCH_LIST="12.0;12.1"
RUN cd /app/exllamav3-anemone && MAX_JOBS="${MAX_JOBS}" pip install -e . --no-build-isolation

# The server. The patch makes TabbyAPI honour a manual memory budget on a single GPU and lets
# the draft model take its own budget — both needed on a unified-memory board.
COPY patches/tabbyapi-unified-memory.patch /app/patches/
RUN git clone "${TABBY_REPO}" /app/tabbyAPI \
    && cd /app/tabbyAPI \
    && git checkout -q "${TABBY_SHA}" \
    && git apply /app/patches/tabbyapi-unified-memory.patch \
    && pip install -e . \
    && pip install uvloop "huggingface_hub[cli]"

# Chat template, sampling preset, server config, scripts.
COPY templates/deepseek_v4.jinja          /app/tabbyAPI/templates/deepseek_v4.jinja
COPY config/sampler_overrides/deepseek_v4.yml /app/tabbyAPI/sampler_overrides/deepseek_v4.yml
COPY config/config.yml                    /app/config/config.yml
COPY scripts/                             /app/scripts/
RUN chmod +x /app/scripts/*.sh \
    && echo "${RECIPE_VERSION}" > /app/VERSION

# Sanity check at build time: the extension must expose the kernels this pack needs.
RUN python -c "import exllamav3; from exllamav3.ext import exllamav3_ext as e; \
    assert all(hasattr(e, s) for s in ('exl3_mgemm','exl3_mgemm_pk','exl3_moe')), 'engine build incomplete'; \
    import exllamav3.anemone_flags as af; print('engine ok:', len(af.SERVING_FLAGS), 'serving flags')"

LABEL org.opencontainers.image.title="DeepSeek V4 Flash on one DGX Spark" \
      org.opencontainers.image.source="https://github.com/0xBakeer/deepseek-v4-flash-spark" \
      org.opencontainers.image.version="${RECIPE_VERSION}" \
      org.opencontainers.image.licenses="MIT" \
      de.deepseek-v4-flash-spark.exllamav3-sha="${EXL3_SHA}" \
      de.deepseek-v4-flash-spark.tabbyapi-sha="${TABBY_SHA}" \
      de.deepseek-v4-flash-spark.torch="${TORCH_VERSION}+cu130"

ENV MODEL_REPO=anoane/DeepSeek-V4-Flash-0731-exl3-2.54bpw \
    MODEL_REVISION=91cf8b7e3cde8833c291bd513590d3fced5e566f \
    MODEL_NAME=deepseek-v4-flash-0731 \
    MODELS_DIR=/models \
    CONFIG=/app/config/config.yml \
    HF_HUB_ENABLE_HF_TRANSFER=0 \
    PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
    EXL3_NO_RLP=1

VOLUME ["/models"]
EXPOSE 8000
WORKDIR /app/tabbyAPI
HEALTHCHECK --interval=30s --timeout=5s --start-period=30m --retries=3 \
    CMD curl -fsS http://127.0.0.1:8000/health || exit 1
ENTRYPOINT ["/app/scripts/entrypoint.sh"]
