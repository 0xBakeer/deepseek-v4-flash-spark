# Measurements

All figures on one DGX Spark (GB10, 128 GB), the v0.1.0 image, the shipped `config.yml`,
model resident and warm. Client-side numbers are what `bench/bench.py` prints: time to first
token from request send, and decode rate = completion tokens ÷ (last chunk − first chunk),
so they exclude prefill and include everything between you and the server. "Server" is
TabbyAPI's own `completion_tokens_per_sec`. The full runs are in [bench/results.md](../bench/results.md).

## Short prompt, streamed

Three runs per cell, `max_tokens: 800`, medians.

| | Story, temperature 1.0 | Story, temperature 0 | Code, temperature 0 | Code, temperature 1.0 |
|---|---|---|---|---|
| prompt tokens | 18 | 18 | 38 | 38 |
| time to first token | 0.60 s | 0.60 s | 1.1 s | 1.1 s |
| decode, client | **30.2 tok/s** | 31.8 tok/s | **57.3 tok/s** | 53.3 tok/s |
| decode, server | 29.7 | 31.2 | 53.9 | 50.3 |
| draft acceptance | 58–71 % | 72–73 % | 90 % | 81–89 % |
| chunks per 794 tokens | ~158 | ~156 | ~49 | ~49 |

*Story*: "Write a short story about a lighthouse keeper (about 500 words)." *Code*: "Write a
Python module implementing a thread-safe LRU cache class with get, put, capacity eviction,
and a small pytest test file. Code only, no explanation."

The same story prompt sent through Open WebUI (server on the LAN, browser on a laptop) came
out at 0.63–0.64 s to first token and 30.4–31.4 tok/s client-side against 29.9–30.8 server —
the network adds nothing measurable.

### What the numbers mean

- **The decode rate is set by the text, not the temperature.** The MTP draft proposes ~6
  tokens per step; the main model verifies them in one pass that costs about 2.6× a
  single-token pass on this weight-bandwidth-bound GPU. Code accepts ~90 % of proposals
  and runs at 53–57 tok/s; a short story accepts 58–73 % and runs at 30–32. Temperature 0
  buys ~5 % on prose. Without the draft model everything runs at ~29 tok/s.
- **Chunk count is the draft step count.** ~49 chunks for 794 code tokens means ~16 tokens
  accepted per step on average; ~158 chunks for the story means ~5. Streaming looks
  "bursty" on code and smooth on prose for that reason.
- **Time to first token on a short prompt is ~0.6 s**, of which prefill of 18 tokens is
  ~0.15 s; the rest is the first draft step and the response plumbing. The code prompt's
  1.1 s includes a longer first step.

## Prefill

| Prompt | Prefill | Rate | Peak memory |
|---|---|---|---|
| 8,800 tokens | ~13 s | 580–730 tok/s | — |
| 100,000 tokens | 125 s | ~800 tok/s | — |
| 300,000 tokens | 374 s | ~800 tok/s | 106 GB used / 15 GB available |
| 600,000 tokens (1M config) | 938 s | ~640 tok/s | 113 GB used / 8 GB available |

Prefill rate is flat to 300k thanks to sparse attention; the 1M configuration is slower
because there is little memory left for activation buffers. Needle-in-a-haystack retrieval
was correct at every one of those lengths.

## Decode at long context

At the 384k configuration, with an 8.8k-token prompt already in context, decode on
structured output measured 44–53 tok/s across the settings sweep — the same band as the
short-prompt code figure. Decode does not fall off with context length on this pack
because the sparse cache read stays small.

## Memory

| | Used | Available |
|---|---|---|
| idle, model + draft + caches resident | 106 GB | 15 GB |
| during a 300k-token prefill | 106 GB | 15 GB |
| 1M-token configuration, idle | 108 GB | 12 GB |

Cache pool sizes measured with the engine's own accounting: main 0.84 GiB at 131k, 1.68 GiB
at 256k, 2.52 GiB at 384k; draft 0.4 / 0.75 / 1.1 GiB.

## Things that do not move the needle

Tried and measured within ±2 tok/s of the shipped configuration: a stricter or looser
draft confidence threshold, FP8 or 8-bit cache modes (ignored for the sparse layers anyway),
dynamic draft length, prefill graph capture, `chunk_size` 4096. The GPU is reading weights
the whole time; the levers that matter are how many tokens each weight read produces
(the draft) and how many requests share it (`max_batch_size`).

## Reproducing

```bash
./run.sh bench                                                  # the story prompt, temperatures 1.0 and 0
./run.sh bench --temps 0 --prompt "Write a Python module ..."   # any prompt you like
```

Run it on an idle server: with `max_batch_size: 1` another request in flight shows up as
queueing time in your time-to-first-token.
