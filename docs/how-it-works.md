# How it works

DeepSeek V4 Flash is a 284-billion-parameter mixture-of-experts model: 43 layers, 256 routed
experts per layer of which 6 fire per token, a multi-token-prediction (MTP) head, and DeepSeek
Sparse Attention (DSA) with a native 1M-token window. In its released FP8 form it does not fit
in 128 GB. This recipe is the set of decisions that make it fit on one DGX Spark *and* leave
enough memory for a long context and a speculative draft.

## The weights: exl3 at 2.54 bits per weight

The pack is [`anoane/DeepSeek-V4-Flash-0731-exl3-2.54bpw`](https://huggingface.co/anoane/DeepSeek-V4-Flash-0731-exl3-2.54bpw)
— 92 GB on disk, 13 safetensors shards, MTP head included.

**exl3** is exllamav3's weight format: trellis-coded quantisation, where each group of weights
is stored as an index into a learned lattice rather than as scaled integers. It reaches useful
quality at bit-rates where integer formats fall apart, which is what a 284B model in 128 GB
requires.

**2.54 bpw is not uniform across the model.** The pack's author assigns one bit-width per layer
— 20 layers at 2 bits, 23 at 3 bits — chosen from measured quantisation hardness on calibration
data. The attention, shared experts and the output head stay at higher precision (head at 6
bits), and the MTP head is quantised at 3 bits so it remains a usable draft model.

The pack needs the **anemone** fork of exllamav3 to load: it carries the per-layer allocation
metadata and the DeepSeek V4 architecture, including the MTP path. Stock exllamav3 does not
load it.

## The engine on aarch64

exllamav3 is written for x86 workstations. Its GPU kernels are plain CUDA and compile for the
GB10 (`sm_121`) unchanged, but two pieces are x86-only:

- the CPU-offload MoE kernels (AVX2 / AVX-512 intrinsics), and
- the tensor-parallel CPU all-reduce.

Neither is on the single-GPU serving path. `patches/exllamav3-anemone-aarch64.patch` excludes
those sources on aarch64, stubs their symbols so the extension still links, and replaces the
x86 `pause` spin hint with the AArch64 `yield`. Every kernel that actually runs is the upstream
kernel.

## Memory on a unified-memory board

The Spark has no separate VRAM: weights, KV cache, draft model and the operating system's page
cache all come out of the same 128 GB. Two things follow.

**The engine must be given a budget, not left to measure "free" memory.** `cudaMemGetInfo` on
this board reports free memory *excluding* the page cache. After the first run the 92 GB of
weights sit in the page cache, "free" reads a few GB, and an auto-sized load refuses to start.
`patches/tabbyapi-unified-memory.patch` makes TabbyAPI honour a manual `gpu_split` on a single
GPU — a fixed 106 GB budget for the main model and 8 GB for the draft — instead of sizing from
the free figure.

**Running out of memory is slow, not fast.** Push available memory to zero and the box pages
for a long time with SSH unresponsive rather than failing. The container runs a watchdog that
kills the server when available memory drops under 4 GB, so a misconfiguration turns into a
restart instead of a hung machine. Never start two model loads at once.

At the shipped configuration the box idles at roughly **106 GB used / 15 GB available** with
the model, the draft and both cache pools resident.

## The context: 384k per request, 768k of pool

DSA stores a compressed, sparse cache. Measured with the engine's own `storage_size()`, the
main cache pool is **0.84 GiB at 131k, 1.68 GiB at 256k, 2.52 GiB at 384k**, and the draft's
pool adds 0.4 / 0.75 / 1.1 GiB. That is why the recipe can afford `cache_size` at twice
`max_seq_len`: the paged pool then holds two full-length conversations, and the prefix cache
serves a follow-up turn from cache instead of re-reading the whole prompt.

Context here is bounded by *prefill time*, not memory: a 300k-token prompt takes about six
minutes to read at ~800 tok/s. The model itself is trained to 1M via YaRN (×16 over a 64k
base), and a 1M configuration does load — at 108 GB used / 12 GB free, with a 600k-token
prompt taking 15 minutes to prefill — but that leaves too little headroom to be the default.

Quantised cache modes (`cache_mode: 8,8` etc.) are accepted by the config and **ignored** for
DSA layers; the pools are always FP16. The recipe says FP16 so the config tells the truth.

## Speculative decoding with the MTP head

DeepSeek V4 ships a one-token MTP head. exllamav3-anemone uses it as a draft model
(`draft_mode: mtp`): the draft proposes several tokens, the main model verifies them in one
forward pass, and every accepted token is exact — drafting changes speed, never output.

On the GB10 the main model's forward is bound by reading the weights, so a verify pass over
five tokens costs about 2.6× a single-token pass rather than 5×. The gain therefore depends
almost entirely on how many drafted tokens get accepted — and that is a property of the
*text*, far more than of the sampling settings:

| Output | Acceptance | Decode |
|---|---|---|
| code, structured output, formats with a predictable next token | 85–90 % | 50–57 tok/s |
| free prose (a short story) | 58–72 % | 30–32 tok/s |
| no draft model at all | — | ~29 tok/s |

Where every next token is nearly forced — a closing bracket, the next word of an identifier,
the second half of a pattern the file has already established — the draft is right almost
every time and the main model verifies six tokens for the price of about two and a half. In
open prose there are many acceptable next words, the draft picks one, the main model picks
another, and at ~60 % acceptance the drafter pays for itself and no more. Temperature moves
the figure by a few percent (prose at temperature 0 is 31.8 tok/s against 30.2 at 1.0), the
content moves it by a factor of two. The numbers are in [measurements.md](measurements.md).

## The chat template

DeepSeek publishes no Jinja template for V4 — the release ships a Python encoder,
`encoding_dsv4.py`, and the README says so. `templates/deepseek_v4.jinja` is a line-by-line
port of that encoder, verified byte-identical against it on eleven conversation shapes (plain,
system prompt, multi-turn, thinking on/off with each effort level, tools with and without a
system prompt, tool-call round trips, tool calls inside a thinking conversation). What it
encodes, and how to drive it, is in [chat-template.md](chat-template.md).
