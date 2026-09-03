# Configuration

The whole server is one file, `config/config.yml`, mounted read-only into the container.
Edit it, `./run.sh stop`, `./run.sh serve`. This page explains every value that matters and
what happens when you move it.

## Context

```yaml
max_seq_len: 393216
cache_size: 786432
chunk_size: 2048
max_batch_size: 1
```

- **`max_seq_len`** is the longest single request (prompt + output) the server accepts:
  384k tokens. Requests over it are rejected with a clear error rather than truncated.
- **`cache_size`** is the paged cache pool, in tokens, shared by all sequences and by the
  prefix cache. At twice `max_seq_len` two full-length conversations stay cached, so the
  next turn of a long chat pays for its new tokens only. Cost at these values: 2.5 GiB main
  + 1.1 GiB draft. Halving both saves ~1.8 GiB; you will not notice.
- **`chunk_size`** is the prefill batch. 2048 is the throughput plateau on this GPU; 4096
  gains nothing measurable and needs more activation memory.
- **`max_batch_size: 1`** serves one request at a time; further requests queue and are
  answered in order. Decode on this board is bound by reading the weights, so two
  concurrent sequences would each run at nearly full speed — `2` is the first thing to try
  if you serve several users, at the cost of a second set of activations (a few GB) and
  a second slot in the cache pool.

Going longer: `max_seq_len: 1048576` with `cache_size` to match loads on the 128 GB board
(about 12 GB left free) and a 600k-token prompt is answered correctly — after a fifteen-minute
prefill. It is a working configuration, not a comfortable one, which is why 384k ships.

## Memory

```yaml
gpu_split_auto: false
gpu_split: [106]
draft_model:
  draft_gpu_split: [8]
```

Budgets in GB for the main model and the draft. Together with the caches the box idles at
roughly 106 GB used and 15 GB available. Do not raise `gpu_split` to "use the rest": the
operating system, the page cache that keeps the next restart fast, and the prefill
activations all live in the same pool, and the failure mode when it runs out is a machine
that pages for half an hour, not an error. The container's watchdog kills the server when
available memory drops under `WATCHDOG_MIN_AVAIL_GB` (default 4) for exactly this reason.

`cuda_malloc_async: true` under `memory:` uses the CUDA asynchronous allocator; with
`PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` (set in the image) it keeps the long-context
activation buffers from fragmenting.

## Sampling

`sampling.override_preset: deepseek_v4` loads `config/sampler_overrides/deepseek_v4.yml`:
temperature 1.0, top_p 1.0, every other sampler neutral. That is what DeepSeek recommends,
and it is what a request gets when it sends no sampling parameters. A request that sends its
own values wins (`force: false`).

Temperature has only a small effect on speed. The draft model's proposals are accepted when
the main model agrees with them, and how often that happens depends on the text being
generated: code and structured output decode at 50–57 tok/s, free prose at 30–32, at either
temperature (greedy adds about 5 % on prose — see [measurements.md](measurements.md)). So
choose the temperature on quality grounds alone: `0` where you would have chosen greedy
anyway (extraction, classification, strict formats); the default 1.0 for open-ended
writing, where greedy decoding is prone to repetition loops on long output — DeepSeek's
recommendation exists for that reason.

`top_p: 0.95` is DeepSeek's suggestion for agentic (tool-calling) use; send it per request
from your agent rather than changing the preset for everyone.

## Reasoning

```yaml
reasoning: true
reasoning_start_token: "<think>"
reasoning_end_token: "</think>"
template_vars_default:
  reasoning_effort: low
```

Thinking is off by default: the template ends the prompt with `</think>` and the model
answers directly. Any request can turn it on:

```json
"chat_template_kwargs": {"thinking": true, "reasoning_effort": "high"}
```

or, for clients that only speak the OpenAI fields, a top-level `"reasoning_effort": "high"`
(`medium`/`max` too), `"enable_thinking": true`, or `"reasoning": {"effort": "high"}`. The
template derives `thinking` from those only while no explicit `thinking` is set, which is why
`template_vars_default` must not contain `thinking` — a default there would pin it.

Reasoning tokens are then returned in `reasoning_content` (and streamed as
`delta.reasoning_content`), never mixed into `content`. `reasoning_effort` is `low`, `high`
or `max` and is only read when thinking is on. Flip the defaults here if most of your traffic
wants reasoning. When tools are present the template keeps reasoning on for every turn, as
the reference encoder does.

## Tool calling

`tool_format: deepseek_v4` makes the server parse the model's DSML tool-call blocks into
OpenAI-style `tool_calls` with `finish_reason: "tool_calls"`. Without it the block arrives as
plain text in `content`. Leave it set. See [api.md](api.md#tool-calling).

## The draft model

```yaml
draft_model:
  draft_mode: mtp
  draft_gpu_split: [8]
  draft_cache_mode: FP16
```

Uses the pack's MTP head as the speculative draft. Remove the whole block to run without it:
you lose the speed-up on predictable text (~55 → ~29 tok/s on code), gain 8 GB, and nothing else changes — outputs
are the same distribution either way.

## Network and auth

```yaml
host: 0.0.0.0
port: 8000
disable_auth: true
```

The container listens on all interfaces *inside* the container; `compose.yaml` publishes it on
`127.0.0.1:8000` only, so nothing outside the machine can reach it. To expose it on the LAN,
change the port mapping in `compose.yaml` to `"8000:8000"` **and** set `disable_auth: false` —
the server then generates `api_key` and `admin_key` in `api_tokens.yml` on first start
(`./run.sh logs` prints them) and clients send `Authorization: Bearer <api_key>`.

## Logging

All three prompt/parameter/request logs are off. Turning `log_prompt` on writes every
conversation into the container log; do it for debugging a template problem and turn it off
again.

## Environment variables

Set in `compose.yaml` or `.env`:

| Variable | Default | Meaning |
|---|---|---|
| `MODELS_DIR` | `./models` | host directory holding the weights |
| `PORT` | `8000` | host port, bound on 127.0.0.1 |
| `RECIPE_VERSION` | contents of `VERSION` | image tag to pull/run |
| `HF_TOKEN` | unset | Hugging Face token, only needed if your download is rate-limited |
| `WATCHDOG_MIN_AVAIL_GB` | `4` | kill the server when `free -g` "available" drops below this |
