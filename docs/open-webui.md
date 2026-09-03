# Open WebUI

The server is a plain OpenAI-compatible endpoint, so Open WebUI needs one connection and no
plugins.

## Connect

*Admin Panel → Settings → Connections → OpenAI API → add*:

- **URL**: `http://<spark-host>:8000/v1` (if Open WebUI runs on the Spark itself and in
  Docker, use `http://host.docker.internal:8000/v1`, and change the port mapping in
  `compose.yaml` so the port is reachable from the Open WebUI container)
- **Key**: anything non-empty while `disable_auth: true`; the generated `api_key` otherwise

`deepseek-v4-flash-0731` appears in the model picker once the connection is verified.

## Make it feel fast

Two things dominate what a chat user perceives, and both are on the Open WebUI side.

**Keep tools off the everyday model.** Every tool or MCP server attached to a model row is
serialised into every prompt. Forty tools is around ten thousand tokens of prompt per turn;
at ~600 tok/s prefill that is fifteen seconds before the first character, on every message.
Create two model entries from the same connection: one bare for chat, one with the tools for
agent work. Also turn off *Memory* for the chat entry — its injected block sits at the *start*
of the prompt and changes on every request, which defeats the prefix cache.

**Leave the sampling alone.** With temperature unset the server applies DeepSeek's
recommended 1.0 / 1.0. Speed is a property of the output, not of the temperature: code
streams at 50+ tok/s, prose at ~30, either way.

## Thinking

Open WebUI renders `reasoning_content` as a collapsible thinking block. Thinking is off by
default on the server. Open WebUI already sends its *Reasoning Effort* setting as a top-level
`reasoning_effort`, so the simplest switch is that field: set it to `high` (or `medium`, `max`)
in a model entry's *Advanced Params*, or per chat in *Chat Controls*, and that entry thinks.
`low` (or unset) keeps thinking off. A separate "Thinking" entry with `reasoning_effort: high`
next to the plain one is a good way to have both in the model picker.

The explicit form still works, via *Custom Parameters* (or a filter):

```json
{"chat_template_kwargs": {"thinking": true, "reasoning_effort": "high"}}
```

Tokens of reasoning are billed against the same generation speed, so a `high` entry answers
hard questions better and everything else slower.

## Streaming looks "chunky"

Text arrives about six tokens at a time every ~150 ms. That is the draft model's step size,
not buffering; the client-side and server-side tok/s figures in `./run.sh bench` agree to
within 2 %.
