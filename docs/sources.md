# Sources

Everything the recipe is built on, with the exact versions used for the published
measurements.

## Model and weights

- DeepSeek-V4-Flash-0731 — the model, its README (sampling recommendation, the reference
  chat encoder `encoding/encoding_dsv4.py`), and licence:
  https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash-0731
- `anoane/DeepSeek-V4-Flash-0731-exl3-2.54bpw` — the exl3 quantisation used here, revision
  `91cf8b7e3cde8833c291bd513590d3fced5e566f` (13 shards, 92 GB, MTP head included, per-layer
  2/3-bit allocation, 6-bit head): https://huggingface.co/anoane/DeepSeek-V4-Flash-0731-exl3-2.54bpw

## Engine and server

- exllamav3 — the exl3 format and engine: https://github.com/turboderp-org/exllamav3
- `anoane/exllamav3-anemone` at `c6d2e3eea40dcd15947f55974bde3555a550a157` — the fork that
  loads the per-layer pack and provides the DeepSeek V4 MTP draft path:
  https://github.com/anoane/exllamav3-anemone
- TabbyAPI at `4a4f9f44820303593844f092d424bb7506008733` — the OpenAI-compatible server:
  https://github.com/theroyallab/tabbyAPI

## Platform

- Base image `nvidia/cuda:13.0.2-devel-ubuntu24.04` (arm64)
- PyTorch 2.11.0+cu130 (aarch64 wheel from https://download.pytorch.org/whl/cu130)
- NVIDIA driver 580.173.02, CUDA 13.0, Docker 29.x, nvidia-container-toolkit 1.19.x
- DGX Spark: GB10, 128 GB unified memory, `TORCH_CUDA_ARCH_LIST="12.0;12.1"`
