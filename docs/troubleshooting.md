# Troubleshooting

**`./run.sh serve` waits and never becomes healthy.** Look at `./run.sh logs`. A first start on
a cold disk reads 92 GB and can take several minutes; a warm start is ~40 s. If the log ends
in a CUDA out-of-memory or the container restarts: something else holds memory — another
model server, a build, a browser with many tabs. Everything in this recipe assumes ~106 GB is
available to it.

**"Insufficient VRAM" / the load refuses on a restart but worked the first time.** The
unified-memory patch is what prevents this; it means you are running an unpatched TabbyAPI
(native install without step 3's `git apply`) or set `gpu_split_auto: true`. The engine then
sizes itself from "free" memory, which on this board excludes the page cache holding the
weights from the last run.

**The machine becomes unresponsive for a long time instead of failing.** Memory ran out. Wait
it out (the OOM killer will act, eventually) or hard-reset. Then find what else was running:
two model loads at once is the usual cause. The container's watchdog kills the server below
4 GB available to keep this from happening; if you run natively, keep the equivalent
(`scripts/watchdog.sh`) running too.

**Weights download stops or errors.** `./run.sh setup` again — the download resumes. If
Hugging Face rate-limits you, put a token in `HF_TOKEN`. The download script checks that
every file listed in `model.safetensors.index.json` is present before it reports success.

**Answers start with the model talking to itself ("Let me analyse the request…").** The
server is not using the shipped template: check that `prompt_template: deepseek_v4` is set
and, on a native install, that `templates/deepseek_v4.jinja` sits inside `tabbyAPI/` and the
server was started from that directory. See [chat-template.md](chat-template.md).

**Tool calls come back as text starting with `<｜DSML｜tool_calls>`.** `tool_format:
deepseek_v4` is missing from the config.

**Time to first token is long (10 s+) on short questions.** Either the prompt is not short —
count tools; a client that attaches thirty tools sends ~10k tokens per turn — or another
request is running and yours is queued (`max_batch_size: 1`).

**Decode is ~30 tok/s on one request and ~55 on another.** That is the speculative draft:
it is accepted on predictable text (code, JSON, tables, lists) and rejected on open prose,
and the decode rate follows the acceptance rate. Both figures are normal; see
[measurements.md](measurements.md).

**Long output goes into a loop.** Greedy decoding on long creative text. Use temperature 1.0
(the default) for that kind of request; loops are rare there.

**A request over ~393k tokens is rejected.** That is `max_seq_len`. Raise it (and
`cache_size`) if you must — up to 1M loads — and budget prefill at ~600–800 tok/s.

**`docker: could not select device driver "nvidia"`.** Install `nvidia-container-toolkit`,
run `sudo nvidia-ctk runtime configure --runtime=docker`, restart Docker.

**Build fails cloning from GitHub inside Docker.** The Dockerfile forces `http.version
HTTP/1.1` for git because some networks break git's HTTP/2 negotiation; if it still fails,
check that the Docker daemon can resolve and reach `github.com` at all
(`docker run --rm ubuntu:24.04 getent hosts github.com`).
