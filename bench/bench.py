#!/usr/bin/env python3
"""Measure what a client actually sees: time to first token and streamed decode rate.

    ./bench/bench.py                                   # defaults: http://127.0.0.1:8000, temperature 1.0 and 0
    ./bench/bench.py --api http://host:8888 --runs 5 --temps 1.0 --max-tokens 800
    ./bench/bench.py --key sk-...                      # if the server has auth on

Decode tok/s is completion_tokens / (last chunk time - first chunk time), i.e. it excludes prefill.
Each row also prints the server's own completion_tokens_per_sec from the usage block so the two
can be compared; if they drift apart, something between you and the server is buffering.
"""
import argparse, json, statistics, sys, time, urllib.request

PROMPT = "Write a short story about a lighthouse keeper (about 500 words)."


def run(api, model, key, temp, max_tokens, prompt):
    body = {"model": model, "stream": True, "stream_options": {"include_usage": True},
            "temperature": temp, "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": prompt}]}
    hdr = {"Content-Type": "application/json"}
    if key:
        hdr["Authorization"] = "Bearer " + key
    req = urllib.request.Request(api.rstrip("/") + "/v1/chat/completions", json.dumps(body).encode(), hdr)
    t0 = time.time(); ts = []; usage = None; chars = 0
    with urllib.request.urlopen(req, timeout=600) as r:
        for line in r:
            if not line.startswith(b"data: ") or b"[DONE]" in line:
                continue
            d = json.loads(line[6:])
            if d.get("choices") and d["choices"][0]["delta"].get("content"):
                ts.append(time.time() - t0); chars += len(d["choices"][0]["delta"]["content"])
            if d.get("usage"):
                usage = d["usage"]
    if not ts or not usage:
        raise SystemExit("no streamed content or no usage block (is stream_options.include_usage supported?)")
    ct = usage["completion_tokens"]
    return {"prompt_tokens": usage["prompt_tokens"], "ttft_s": ts[0], "completion_tokens": ct,
            "gen_s": ts[-1] - ts[0], "client_tok_s": ct / max(ts[-1] - ts[0], 1e-6),
            "server_tok_s": usage.get("completion_tokens_per_sec"), "chunks": len(ts), "chars": chars}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--api", default="http://127.0.0.1:8000")
    ap.add_argument("--model", default="deepseek-v4-flash-0731")
    ap.add_argument("--key", default=None)
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--temps", default="1.0,0")
    ap.add_argument("--max-tokens", type=int, default=800)
    ap.add_argument("--prompt", default=PROMPT)
    a = ap.parse_args()
    for temp in [float(t) for t in a.temps.split(",")]:
        rates = []
        print(f"\n== temperature {temp:g} ==")
        for i in range(1, a.runs + 1):
            r = run(a.api, a.model, a.key, temp, a.max_tokens, a.prompt)
            rates.append(r["client_tok_s"])
            srv = f"{r['server_tok_s']:.1f}" if r["server_tok_s"] else "n/a"
            print(f"run {i}: prompt {r['prompt_tokens']} tok | TTFT {r['ttft_s']:.2f} s | "
                  f"{r['completion_tokens']} tok in {r['gen_s']:.1f} s = {r['client_tok_s']:.1f} tok/s "
                  f"(server {srv}) | {r['chunks']} chunks")
        print(f"median {statistics.median(rates):.1f} tok/s")


if __name__ == "__main__":
    main()
