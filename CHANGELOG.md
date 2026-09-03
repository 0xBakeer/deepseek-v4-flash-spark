# Changelog

What a version means here: this repository is not a library, and nothing imports it. What you
depend on is **the defaults the recipe ships and the measurements taken on them**. So a release
is a measurement epoch — the configuration as it stood, and the figures that belong to it.

- **MAJOR** — the measurement basis changes (new hardware, a different model or pack).
- **MINOR** — a shipped default changes, or the recipe gains a capability. Your numbers move.
- **PATCH** — documentation, corrections, tooling. Your numbers do not move.

Every entry leads with **Defaults that changed**. `./run.sh` and the container print the version
they were launched from. The image is tagged with it: `ghcr.io/0xbakeer/deepseek-v4-flash-spark:<version>`.

## v0.1.1 — 2026-09-03

### Defaults that changed

None that move a number. `template_vars_default` no longer pins `thinking: false`; the
template derives the switch instead, and the rendered prompt is byte-identical for every
request shape v0.1.0 accepted.

### Changed

- Thinking can be switched on with the OpenAI-style fields alone: a top-level
  `reasoning_effort` of `medium`/`high`/`max` (`xhigh` accepted as `max`), `enable_thinking: true`,
  or `reasoning: {"effort": ...}`. Before, only `chat_template_kwargs.thinking` did, and a
  client that sent `reasoning_effort: high` (Open WebUI's Reasoning Effort setting, for one)
  got the effort text with thinking still off. `none`/`low` keep the default chat mode; an
  explicit `chat_template_kwargs.thinking` still wins.
- Docs updated accordingly (API, configuration, chat template, Open WebUI).

## v0.1.0 — 2026-09-02

First release.

### Defaults that changed

Everything — this is the baseline. The configuration as shipped:

| Setting | Value |
|---|---|
| pack | `anoane/DeepSeek-V4-Flash-0731-exl3-2.54bpw` @ `91cf8b7e` |
| engine | exllamav3-anemone @ `c6d2e3e` + aarch64 patch |
| server | TabbyAPI @ `4a4f9f4` + unified-memory patch |
| context | 393,216 per request, 786,432-token cache pool, FP16 |
| memory budget | 106 GB main + 8 GB draft |
| draft | MTP head, `draft_mode: mtp` |
| sampling | temperature 1.0 / top_p 1.0 (DeepSeek's recommendation), overridable per request |
| reasoning | off by default; `chat_template_kwargs.thinking` turns it on; effort low/high/max |
| tools | `tool_format: deepseek_v4` |

### Measured on it

See [bench/results.md](bench/results.md) and the table in the README. Summary: ~0.6 s to
first token on a short prompt; ~30 tok/s streamed prose; 53–57 tok/s streamed code; prefill ~550–800 tok/s; 300k-token needle retrieved in a 374 s prefill.
