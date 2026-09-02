# Raw runs — v0.1.0 (2026-09-02)

DGX Spark, v0.1.0 image, shipped `config.yml`, idle server, `bench/bench.py --runs 3 --max-tokens 800`.
Client tok/s = completion tokens ÷ (last chunk − first chunk). Server = TabbyAPI's `completion_tokens_per_sec`.
Acceptance from the server log (`Draft: accepted / proposed`).

## Story — "Write a short story about a lighthouse keeper (about 500 words)."

### temperature 1.0 (server default)

| run | prompt tok | TTFT | tokens | time | client tok/s | server tok/s | chunks | draft accepted |
|---|---|---|---|---|---|---|---|---|
| 1 | 18 | 0.60 s | 794 | 26.7 s | 29.8 | 29.3 | 156 | 311 / 533 (58.4 %) |
| 2 | 18 | 0.59 s | 794 | 26.3 s | 30.2 | 29.7 | 160 | 310 / 476 (65.1 %) |
| 3 | 18 | 0.60 s | 794 | 25.7 s | 30.9 | 30.3 | 160 | 333 / 466 (71.5 %) |

median **30.2 tok/s**

### temperature 0

| run | prompt tok | TTFT | tokens | time | client tok/s | server tok/s | chunks | draft accepted |
|---|---|---|---|---|---|---|---|---|
| 1 | 18 | 0.60 s | 794 | 24.6 s | 32.3 | 31.7 | 153 | 321 / 448 (71.7 %) |
| 2 | 18 | 0.60 s | 794 | 25.0 s | 31.7 | 31.2 | 157 | 321 / 441 (72.8 %) |
| 3 | 18 | 0.60 s | 794 | 25.0 s | 31.8 | 31.2 | 157 | — |

median **31.8 tok/s**

### the same prompt through Open WebUI (temperature unset → 1.0)

Browser on a laptop, Open WebUI on a separate host, server on the LAN. Measured at Open
WebUI's `/api/chat/completions` with `stream_options.include_usage`.

| run | prompt tok | TTFT | tokens | client tok/s | server tok/s | chunks |
|---|---|---|---|---|---|---|
| 1 | 18 | 0.64 s | 735 | 31.4 | 30.8 | 145 |
| 2 | 18 | 0.63 s | 780 | 30.6 | 30.1 | 158 |
| 3 | 18 | 0.63 s | 794 | 30.4 | 29.9 | 161 |

## Code — "Write a Python module implementing a thread-safe LRU cache class with get, put, capacity eviction, and a small pytest test file. Code only, no explanation."

### temperature 0

| run | prompt tok | TTFT | tokens | time | client tok/s | server tok/s | chunks | draft accepted |
|---|---|---|---|---|---|---|---|---|
| 1 | 38 | 1.47 s | 794 | 13.8 s | 57.7 | 54.3 | 48 | 648 / 714 (90.8 %) |
| 2 | 38 | 1.08 s | 794 | 13.9 s | 57.1 | 53.7 | 49 | 645 / 718 (89.8 %) |
| 3 | 38 | 1.07 s | 794 | 13.9 s | 57.3 | 53.9 | 49 | 645 / 714 (90.3 %) |

median **57.3 tok/s**

### temperature 1.0

| run | prompt tok | TTFT | tokens | time | client tok/s | server tok/s | chunks | draft accepted |
|---|---|---|---|---|---|---|---|---|
| 1 | 38 | 1.11 s | 659 | 12.5 s | 52.7 | 49.2 | 44 | 524 / 648 (80.9 %) |
| 2 | 38 | 1.11 s | 794 | 14.0 s | 56.7 | 53.3 | 49 | 644 / 720 (89.4 %) |
| 3 | 38 | 1.13 s | 794 | 14.9 s | 53.3 | 50.3 | 54 | 630 / 746 (84.5 %) |

median **53.3 tok/s**

## Long context (384k configuration)

| prompt | result | prefill | rate | memory |
|---|---|---|---|---|
| 100,000 tokens, needle | found | 125 s | ~800 tok/s | — |
| 300,000 tokens, needle | found | 374 s | ~800 tok/s | 106 GB used / 15 GB avail |

1M configuration (`max_seq_len: 1048576`): loads at 108 GB used / 12 GB available; 600,000-token
needle found after a 938 s prefill (~640 tok/s) at 113 GB used / 8 GB available.

## Settings sweep at 8.8k context, structured output, temperature 0, 1.5k tokens

Every variant tried — draft length, draft confidence threshold, 8-bit cache modes (ignored
for the sparse layers), dynamic draft length, prefill graph capture — landed in the same band:

| configuration | decode tok/s | draft accepted |
|---|---|---|
| shipped and all variants | 45 – 53 | 85–99 % |
| no draft model | 29 | — |
