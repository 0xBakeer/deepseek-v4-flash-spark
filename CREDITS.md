# Credits

This repository is a thin layer over other people's work. What is ours is the aarch64 port of
the engine, the unified-memory handling in the server, the chat template port, the serving
configuration, the measurements and the documentation. Everything below is somebody else's.

## The model

**[DeepSeek](https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash-0731)** — DeepSeek V4 Flash:
the architecture (sparse attention, MoE, the MTP head that makes speculative decoding free),
the weights, the reference chat encoder the template is ported from, and the sampling
recommendation the preset follows. The weights carry DeepSeek's own licence; read it before
deploying commercially.

## The quantisation

**[anoane](https://huggingface.co/anoane/DeepSeek-V4-Flash-0731-exl3-2.54bpw)** — the exl3
2.54 bpw pack with its per-layer bit allocation and quantised MTP head, and the
[exllamav3-anemone](https://github.com/anoane/exllamav3-anemone) fork that loads it and
drives the MTP draft. Without this pack there is no 284B model in 128 GB.

## The engine

**[turboderp](https://github.com/turboderp-org/exllamav3)** — exllamav3 and the exl3
trellis-coded format. The kernels that run every token are theirs, unchanged; the aarch64
patch only removes what the GB10 cannot compile.

## The server

**[theroyallab](https://github.com/theroyallab/tabbyAPI)** — TabbyAPI, the OpenAI-compatible
front end with the reasoning split, the DSML tool-call parser and the sampler presets this
recipe leans on.

## The platform

**NVIDIA** — the DGX Spark, the CUDA 13 container images, and PyTorch's cu130 aarch64 wheels.
