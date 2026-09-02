# API

The server speaks the OpenAI chat-completions protocol on `http://127.0.0.1:8000/v1`. Any
OpenAI-compatible client works; point it at that base URL with any (or no) API key.

## Endpoints

| Path | What |
|---|---|
| `GET /health` | `{"status": "healthy"}` once the model is loaded — `./run.sh serve` waits on it |
| `GET /v1/models` | lists `deepseek-v4-flash-0731` |
| `POST /v1/chat/completions` | chat, streaming or not, tools, reasoning |
| `POST /v1/completions` | raw completions (you supply the formatted prompt) |
| `GET /v1/model` | the loaded model's parameters (context length, draft, etc.) |

## Plain chat

```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{
    "model": "deepseek-v4-flash-0731",
    "messages": [{"role": "user", "content": "Explain unified memory in three sentences."}]
  }' | jq -r '.choices[0].message.content'
```

No sampling parameters sent → DeepSeek's recommended temperature 1.0 / top_p 1.0.

## Streaming

```bash
curl -sN http://127.0.0.1:8000/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{
    "model": "deepseek-v4-flash-0731",
    "stream": true,
    "stream_options": {"include_usage": true},
    "messages": [{"role": "user", "content": "Write a limerick about a lighthouse."}]
  }'
```

Chunks arrive one per draft step — around six tokens every ~150 ms — so text appears in small
even bursts rather than one token at a time. The final chunk carries `usage` with
`prompt_tokens`, `completion_tokens`, and the server's own `completion_tokens_per_sec`.

## Sampling

```json
"temperature": 0
```

Send your own `temperature` / `top_p` when you want them; unset means DeepSeek's 1.0 / 1.0.
Speed does not hinge on this: code and structured output stream at 50–57 tok/s and free
prose at ~30 tok/s whichever temperature you pick, because the speculative draft is
accepted on predictable text and rejected on open-ended text. Use `0` where you would use
greedy anyway (extraction, classification, strict formats) and the default for long
open-ended writing, where greedy decoding can loop on this model.

## Thinking

```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{
    "model": "deepseek-v4-flash-0731",
    "messages": [{"role": "user", "content": "Is 2^61 - 1 prime? Reason carefully."}],
    "chat_template_kwargs": {"thinking": true, "reasoning_effort": "high"}
  }' | jq '{reasoning: .choices[0].message.reasoning_content, answer: .choices[0].message.content}'
```

`reasoning_effort`: `low` (default when thinking is on), `high`, `max`. Streaming responses
carry reasoning as `delta.reasoning_content` before the first `delta.content`. Budget for it:
a `high` answer to a hard question is routinely several thousand reasoning tokens.

## Tool calling

Standard OpenAI `tools` / `tool_choice`. The server parses the model's DSML block into
`tool_calls`:

```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{
    "model": "deepseek-v4-flash-0731",
    "messages": [{"role": "user", "content": "What is the weather in Lisbon right now?"}],
    "tools": [{"type": "function", "function": {
      "name": "get_weather",
      "description": "Current weather for a city",
      "parameters": {"type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]}
    }}]
  }' | jq '.choices[0] | {finish_reason, tool_calls: .message.tool_calls}'
```

```json
{
  "finish_reason": "tool_calls",
  "tool_calls": [{"id": "…", "type": "function",
                  "function": {"name": "get_weather", "arguments": "{\"city\": \"Lisbon\"}"}}]
}
```

Send the result back as a `{"role": "tool", "tool_call_id": …, "content": …}` message and
continue. In streaming mode the call arrives as `delta.tool_calls`. DeepSeek suggests
`top_p: 0.95` for agentic use. Note that with tools in the prompt the model is *eager* to use
them — a note-taking tool offered alongside "write me a story" will get called — so attach
tools to the requests that need them, not to every request.

## Python

```python
from openai import OpenAI
client = OpenAI(base_url="http://127.0.0.1:8000/v1", api_key="none")

r = client.chat.completions.create(
    model="deepseek-v4-flash-0731",
    messages=[{"role": "user", "content": "Summarise the attached RFC in five bullets.\n\n" + rfc_text}],
    temperature=0,
    extra_body={"chat_template_kwargs": {"thinking": True}},
)
print(r.choices[0].message.reasoning_content)
print(r.choices[0].message.content)
```

## Long prompts

Up to 393,216 tokens per request. Prefill runs at roughly 550–800 tok/s, so a 100k-token
prompt takes about two minutes before the first token and a 300k-token prompt about six.
Set your client's timeout accordingly, and send long conversations in the same order each
turn so the prefix cache serves the unchanged prefix.

## Concurrency

`max_batch_size: 1`: one request generates at a time; the rest wait in a queue and are served
in order. A client that sees a slow time-to-first-token while another request is running is
seeing the queue, not the model — see [configuration.md](configuration.md#context) for
`max_batch_size: 2`.
