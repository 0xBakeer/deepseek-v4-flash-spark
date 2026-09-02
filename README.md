# DeepSeek V4 Flash on a DGX Spark

Run **DeepSeek V4 Flash** — a 284-billion-parameter mixture-of-experts model — on one desktop
box with 128 GB of memory, with a **384k-token context**, thinking mode, tool calling, and an
OpenAI-compatible API. One command to install, one to serve.

What it is, in a sentence: the exllamav3 engine ported to the Spark's aarch64 GB10, a 2.54-bit
exl3 quantisation of the model that fits in 92 GB, the model's own multi-token-prediction head
used as a speculative draft, a chat template ported line-by-line from DeepSeek's reference
encoder, and a memory configuration that keeps the box stable — all in a container.

---

## What you get

Measured on the shipped image, warm, idle server, three runs per cell
([full runs](bench/results.md), [how they were taken](docs/measurements.md)):

| | **Story** (temperature 1.0, the default) | **Story**, temperature 0 | **Code**, temperature 0 | **Code**, temperature 1.0 |
|---|---|---|---|---|
| prompt | 18 tokens | 18 tokens | 38 tokens | 38 tokens |
| time to first token | **0.60 s** | 0.60 s | 1.1 s | 1.1 s |
| decode, what the client sees | **30.2 tok/s** | 31.8 tok/s | **57.3 tok/s** | 53.3 tok/s |
| decode, server-side | 29.7 | 31.2 | 53.9 | 50.3 |
| draft tokens accepted | 58–71 % | 72–73 % | 90 % | 81–89 % |
| chunks per ~800 tokens | ~158 | ~156 | ~49 | ~49 |

The same story prompt through Open WebUI from a laptop: 0.63 s to first token, 30.4–31.4 tok/s.

**What the numbers mean.** Speed is set by the *text*, not the temperature. The model's MTP
head drafts ~6 tokens per step and the main model verifies them in one pass; on code and
other predictable output ~90 % of the drafts are accepted and you get **50–57 tok/s**, on
free prose ~60–70 % are and you get **~30 tok/s**. Temperature 0 adds about 5 % on prose.
Without the draft everything runs at ~29 tok/s. Prefill is ~550–800 tok/s flat out to 300k
tokens, so a 100k-token document takes about two minutes to read and a 300k one about six.

| | |
|---|---|
| Context per request | 393,216 tokens (a 1M configuration loads; see [configuration](docs/configuration.md#context)) |
| Memory at idle | 106 GB used, 15 GB available |
| Disk | 92 GB weights + 12 GB image |
| Thinking | off by default, on per request, effort low / high / max |
| Tools | OpenAI `tools` → parsed `tool_calls` |
| Concurrency | one request at a time, queued (`max_batch_size` is the knob) |

---

## Install

You need a DGX Spark (or another GB10 box with 128 GB unified memory), Docker with the NVIDIA
container toolkit, and about 105 GB of free disk.

```bash
git clone https://github.com/0xBakeer/deepseek-v4-flash-spark.git
cd deepseek-v4-flash-spark
./run.sh setup     # pulls the image (12 GB) and downloads the weights (92 GB, resumable)
./run.sh serve     # starts the server and waits until it answers
```

That is the whole installation. The server is at **`http://127.0.0.1:8000/v1`**:

```bash
curl -s http://127.0.0.1:8000/v1/chat/completions -H 'content-type: application/json' -d '{
  "model": "deepseek-v4-flash-0731",
  "messages": [{"role": "user", "content": "What does a lighthouse keeper do all day?"}]
}' | jq -r '.choices[0].message.content'
```

Other commands: `./run.sh logs`, `./run.sh stop`, `./run.sh bench`, `./run.sh shell`.
`./run.sh serve` waits for the model to load — about 40 s when the weights are in the page
cache, a few minutes from a cold disk.

**Options** (environment variables): `MODELS_DIR` to put the weights somewhere other than
`./models`; `PORT` for a different host port; `BUILD=1 ./run.sh setup` to build the image on
the box instead of pulling it (~20 minutes); `HF_TOKEN` if Hugging Face rate-limits your
download.

**Without Docker**: [docs/build-from-source.md](docs/build-from-source.md) — same pinned
commits, same patches, in a venv.

---

## Use it

**Thinking.** Off by default. Turn it on per request; reasoning comes back in
`reasoning_content`, never mixed into the answer:

```json
"chat_template_kwargs": {"thinking": true, "reasoning_effort": "high"}
```

**Tools.** Standard OpenAI `tools`; the server returns `finish_reason: "tool_calls"` with
parsed arguments. Attach tools to the requests that need them — the model likes to use what it
is given.

**Streaming.** `"stream": true`; add `"stream_options": {"include_usage": true}` to get token
counts and the server's own tok/s in the last chunk.

**Sampling.** Nothing sent → DeepSeek's recommended temperature 1.0 / top_p 1.0. Send your own
to override.

**Open WebUI.** Add the URL as an OpenAI connection; see [docs/open-webui.md](docs/open-webui.md)
for the two settings that decide whether it feels fast.

All of it with examples: [docs/api.md](docs/api.md).

---

## How it works

Short version — the long one is [docs/how-it-works.md](docs/how-it-works.md):

- **Weights**: `anoane/DeepSeek-V4-Flash-0731-exl3-2.54bpw`, an exl3 (trellis-quantised)
  pack with a per-layer bit allocation — 20 layers at 2 bits, 23 at 3 — a 6-bit head and a
  3-bit MTP head. 92 GB.
- **Engine**: exllamav3-anemone, the fork that loads that pack, with a patch that makes it
  build on aarch64 (the x86-only CPU kernels are excluded and stubbed; every GPU kernel is
  upstream's).
- **Server**: TabbyAPI, with a patch that gives the engine a fixed memory budget on the
  Spark's unified memory instead of sizing from a "free" figure that excludes the page cache.
- **Context**: sparse attention makes the cache tiny (2.5 GiB at 384k), so the limit is
  prefill time, not memory. 384k per request, a 768k pool so the prefix cache holds two full
  conversations.
- **Speed**: the pack's MTP head as speculative draft. Exact outputs, ~2× on predictable text.
- **Template**: a port of DeepSeek's `encoding_dsv4.py`, verified byte-identical on eleven
  conversation shapes, so thinking on/off, effort levels and tool calls behave as the model
  was trained.
- **Stability**: a memory budget with 15 GB of headroom and a watchdog that turns "out of
  memory" into a restart instead of a half-hour of paging.

---

## Repository

```
run.sh                     setup / serve / logs / stop / bench / shell
compose.yaml               the container: GPU, memory, ports, volumes
Dockerfile                 how the image is built (pinned commits, patches, compile flags)
config/config.yml          the server configuration, every value explained
config/sampler_overrides/  DeepSeek's recommended sampling as a preset
templates/deepseek_v4.jinja  the chat template
patches/                   the aarch64 engine port and the unified-memory server patch
scripts/                   entrypoint, weight download, memory watchdog, native launcher
bench/                     bench.py and the raw results
docs/                      everything below
```

| | |
|---|---|
| [docs/how-it-works.md](docs/how-it-works.md) | the quantisation, the engine port, memory, context, the draft, the template |
| [docs/configuration.md](docs/configuration.md) | every setting in `config.yml` and what moving it does |
| [docs/api.md](docs/api.md) | chat, streaming, thinking, tools, Python, long prompts |
| [docs/chat-template.md](docs/chat-template.md) | what the template encodes and how to drive it |
| [docs/open-webui.md](docs/open-webui.md) | connecting a chat UI and keeping it fast |
| [docs/measurements.md](docs/measurements.md) | the figures above, prefill, memory, what did not help |
| [docs/build-from-source.md](docs/build-from-source.md) | building the image, native install, what the patches are |
| [docs/troubleshooting.md](docs/troubleshooting.md) | symptoms → causes |
| [docs/sources.md](docs/sources.md) | exact versions of everything |
| [CHANGELOG.md](CHANGELOG.md) | versions are measurement epochs |
| [CREDITS.md](CREDITS.md) | whose work this rests on |

Licence: MIT for everything in this repository. The model weights carry DeepSeek's licence.
