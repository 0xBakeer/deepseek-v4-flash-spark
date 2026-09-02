# The chat template

DeepSeek V4 ships no Jinja chat template. The reference for how a conversation is turned into
tokens is a Python file in the model release, `encoding/encoding_dsv4.py`, and the release
README points at it. Every Jinja template you find for V4 is somebody's reconstruction; most
get the thinking switch wrong, and the visible symptom is a model that "thinks out loud" in
the answer even though you asked it not to.

`templates/deepseek_v4.jinja` is a direct port of `encode_messages()` from that file. It was
checked byte-for-byte against the reference encoder on eleven conversation shapes — plain,
system prompt, multi-turn, thinking on and off at every effort level, tools with and without
a system prompt, a tool-call round trip, and tool calls inside a thinking conversation. The
only difference is whitespace inside JSON tool schemas, which the tokenizer does not care
about.

## What the encoder does

Written out, with `<BOS>` for the model's begin-of-sequence token:

**Chat (thinking off)** — the prompt ends with `</think>`, which tells the model the thinking
phase is already over:

```
<BOS>{system prompt, bare, if any}<｜User｜>{user}<｜Assistant｜></think>
```

**Thinking on** — the prompt ends with `<think>` and, in thinking mode only, the effort text
comes first, before anything else:

```
<BOS>{effort text}{system prompt}<｜User｜>{user}<｜Assistant｜><think>
```

`reasoning_effort: low` has empty effort text. `high` and `max` inject DeepSeek's own
paragraphs asking for thorough deliberation; they are copied verbatim from the encoder.

**Earlier assistant turns** are encoded as `</think>{content}<EOS>` — previous reasoning is
dropped (`drop_thinking=True` in the reference) so a long thinking conversation does not fill
its own context with old deliberations.

**Tools** add a `## Tools` block after the system prompt describing the DSML call syntax and
listing the JSON schemas. Tool calls the model made are re-encoded as
`<｜DSML｜tool_calls>…</｜DSML｜tool_calls>` blocks; tool results are wrapped in
`<tool_result>` elements and consecutive results are merged into one user turn. When tools are
present, the reference keeps reasoning on every assistant turn (`drop_thinking=False`), and so
does the template.

## Driving it from the API

The template reads three variables: `thinking`, `reasoning_effort`, and the request's `tools`.
Defaults come from `template_vars_default` in `config.yml` (thinking off, effort low). Any
request can override them:

```json
{
  "model": "deepseek-v4-flash-0731",
  "messages": [...],
  "chat_template_kwargs": {"thinking": true, "reasoning_effort": "max"}
}
```

`template_vars` is accepted as an alias of `chat_template_kwargs`, and a top-level
`reasoning_effort` field works as well. With thinking on, the server splits the output at
`</think>` and returns the reasoning in `reasoning_content`.

## If you edit it

Change it only against the reference. The check is mechanical: render a conversation with
the template, encode the same conversation with `encoding_dsv4.py`, compare the strings. A
template that "looks right" but differs by one `<think>` changes how the model behaves on
every request.
