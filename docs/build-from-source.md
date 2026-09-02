# Building from source

Two ways to get the exact stack the image contains without pulling the image.

## Build the image yourself

```bash
BUILD=1 ./run.sh setup
```

`docker compose build` runs the `Dockerfile`: CUDA 13.0.2 devel base, PyTorch 2.11.0 (cu130
aarch64 wheel), the engine cloned at its pinned commit with the aarch64 patch applied and
compiled for `sm_120`/`sm_121`, TabbyAPI at its pinned commit with the unified-memory patch,
the template, the sampler preset and the scripts. The engine compile takes about twenty
minutes with `MAX_JOBS=16` and needs roughly 20 GB of free memory while it runs — **stop the
server first** if one is running on the same box, or the build will starve it.

The pins are `ARG`s at the top of the Dockerfile; bump them there.

## Native install (no Docker)

For people who would rather have a venv. Same commits, same patches, same config.

```bash
ROOT=~/deepseek-v4-flash-spark-native
mkdir -p "$ROOT" && cd "$ROOT"

# 1. Python + PyTorch
python3 -m venv venv && . venv/bin/activate
pip install --upgrade pip wheel setuptools ninja
pip install "torch==2.11.0+cu130" --index-url https://download.pytorch.org/whl/cu130

# 2. The engine, pinned + patched, compiled for the GB10
git clone https://github.com/anoane/exllamav3-anemone.git
( cd exllamav3-anemone \
  && git checkout -q c6d2e3eea40dcd15947f55974bde3555a550a157 \
  && git apply /path/to/recipe/patches/exllamav3-anemone-aarch64.patch \
  && TORCH_CUDA_ARCH_LIST="12.0;12.1" MAX_JOBS=16 pip install -e . --no-build-isolation )

# 3. TabbyAPI, pinned + patched
git clone https://github.com/theroyallab/tabbyAPI.git
( cd tabbyAPI \
  && git checkout -q 4a4f9f44820303593844f092d424bb7506008733 \
  && git apply /path/to/recipe/patches/tabbyapi-unified-memory.patch \
  && pip install -e . && pip install uvloop "huggingface_hub[cli]" )
cp /path/to/recipe/templates/deepseek_v4.jinja tabbyAPI/templates/
cp /path/to/recipe/config/sampler_overrides/deepseek_v4.yml tabbyAPI/sampler_overrides/

# 4. Weights (92 GB) — the revision is the one everything here was measured on
hf download anoane/DeepSeek-V4-Flash-0731-exl3-2.54bpw \
   --revision 91cf8b7e3cde8833c291bd513590d3fced5e566f \
   --local-dir models/deepseek-v4-flash-0731

# 5. Config: same file, native paths
sed -e "s#model_dir: /models#model_dir: $ROOT/models#" /path/to/recipe/config/config.yml > config.yml
```

Run it with `scripts/serve-native.sh` (it sets `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`
and `EXL3_NO_RLP=1`, changes into `tabbyAPI/` so `templates/` resolves, and execs
`main.py --config`):

```bash
ROOT=~/deepseek-v4-flash-spark-native /path/to/recipe/scripts/serve-native.sh
```

Prerequisites on the host: CUDA 13.0 toolkit at `/usr/local/cuda`, `ninja-build`, and a driver
of the 580 series. `uvloop` is installed by hand because TabbyAPI's `pyproject.toml` only
lists it for x86_64.

## What the patches are

**`patches/exllamav3-anemone-aarch64.patch`** — the engine builds on aarch64. `setup.py`
excludes the x86-only sources (AVX2/AVX-512 CPU-MoE kernels and the tensor-parallel CPU
all-reduce), a new `arm64_stubs.cpp` provides their symbols so the extension links, and the
`_mm_pause` spin hint becomes `yield` in the two files that use it. No GPU kernel is touched.

**`patches/tabbyapi-unified-memory.patch`** — two changes in `backends/exllamav3/model.py`:
on a single GPU a manual `gpu_split` is honoured as a fixed budget (upstream only reads it
for multi-GPU and otherwise sizes from `mem_get_info().free`, which on unified memory
excludes the page cache and refuses to load after the first warm restart); and the draft
model's load no longer passes both a reserve and a use budget, which the engine asserts on.

Both patches apply to the pinned commits with `git apply`; they will need a look when the
pins move.
