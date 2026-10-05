#!/usr/bin/env python3
"""Phase B: Execution State + Information, 5 conditions x C/N."""
import argparse, datetime, hashlib, json, pathlib, time, urllib.error, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent
CONDITIONS = ["F_PRESENT", "F_ABSENT", "F_STALE", "F_CONFLICTING", "F_IRRELEVANT"]
INFO_FILES = {
    "F_PRESENT": "INFO_PRESENT.txt",
    "F_ABSENT": "INFO_ABSENT.txt",
    "F_STALE": "INFO_STALE.txt",
    "F_CONFLICTING": "INFO_CONFLICTING.txt",
    "F_IRRELEVANT": "INFO_IRRELEVANT.txt",
}
MODELS = {
    "C": {"model_id": "C-gemma4-unified", "repo_id": "mlx-community/gemma-4-12b-coder-fable5-composer2.5-4bit", "inference": {"temperature": 0, "max_tokens": 1024, "stream": False}},
    "N": {"model_id": "N-nail-qwen3-5-moe", "repo_id": "peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX", "inference": {"temperature": 0, "max_tokens": 1024, "stream": False}},
}

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def wj(p, v): p.write_text(json.dumps(v, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
def gj(url):
    with urllib.request.urlopen(url, timeout=10) as r: return json.loads(r.read())

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--base-url", default="http://127.0.0.1:8000/v1")
    p.add_argument("--run-root", type=pathlib.Path, required=True)
    p.add_argument("--model", choices=tuple(MODELS), required=True)
    p.add_argument("--resume", action="store_true")
    args = p.parse_args()
    model = MODELS[args.model]
    if args.run_root.exists() and not args.resume: raise RuntimeError(f"run root exists: {args.run_root}")
    args.run_root.mkdir(parents=True, exist_ok=True)
    health = gj(args.base_url.rstrip("/").removesuffix("/v1") + "/health")
    models = gj(args.base_url.rstrip("/") + "/models")
    active_ids = {x.get("id") for x in models.get("data", [])}
    if model["repo_id"] not in active_ids: raise RuntimeError(f"loaded model mismatch; expected {model['repo_id']}, got {sorted(active_ids)}")
    (args.run_root / "RUNTIME_META.json").write_text(json.dumps({"health": health, "models": models, "selected": model}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    template = (ROOT / "prompts" / "TEMPLATE_B.prompt.txt").read_text(encoding="utf-8")
    for cond in CONDITIONS:
        cell = args.run_root / model["model_id"] / cond
        done = cell / "RUN_RECORD.json"
        if args.resume and done.exists() and json.loads(done.read_text()).get("http_status") == 200: continue
        cell.mkdir(parents=True, exist_ok=True)
        info = (ROOT / "prompts" / INFO_FILES[cond]).read_text(encoding="utf-8")
        prompt = template.replace("{INFORMATION_SECTION}", info)
        (cell / "prompt.rendered.txt").write_text(prompt, encoding="utf-8")
        payload = {"messages": [{"role": "user", "content": prompt}], "model": model["repo_id"], **model["inference"]}
        wj(cell / "request.json", payload)
        req = urllib.request.Request(args.base_url.rstrip("/") + "/chat/completions", data=json.dumps(payload, ensure_ascii=False).encode("utf-8"), headers={"Content-Type": "application/json"}, method="POST")
        started = time.time()
        try:
            with urllib.request.urlopen(req, timeout=300) as r: status, raw = r.status, r.read()
        except urllib.error.HTTPError as exc: status, raw = exc.code, exc.read()
        elapsed = round(time.time() - started, 6)
        (cell / "response.raw.json").write_bytes(raw)
        try: rj = json.loads(raw)
        except json.JSONDecodeError: rj = {"_undecoded": raw.decode("utf-8", errors="replace")}
        wj(cell / "response.json", rj)
        ch = rj.get("choices", []) if isinstance(rj, dict) else []
        content = ch[0].get("message", {}).get("content") if ch and isinstance(ch[0], dict) else None
        (cell / "final-answer.txt").write_text(content or "", encoding="utf-8")
        wj(cell / "RUN_RECORD.json", {"condition": cond, "model_id": model["model_id"], "repo_id": model["repo_id"], "http_status": status, "elapsed_seconds": elapsed, "prompt_sha256": sha(cell / "prompt.rendered.txt"), "info_sha256": sha(ROOT / "prompts" / INFO_FILES[cond]), "response_sha256": sha(cell / "response.raw.json"), "created_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds")})
        if status != 200: raise RuntimeError(f"{cond}: HTTP {status}")
        print(json.dumps({"condition": cond, "model": model["model_id"], "status": status, "elapsed": elapsed}))

if __name__ == "__main__": main()
