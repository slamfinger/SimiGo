#!/usr/bin/env python3
"""Run the frozen four-cell authorization-boundary matrix."""
import argparse, datetime, hashlib, json, pathlib, time, urllib.error, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent
STATES = (
    ("AUTHZ_ALLOWED", "MAY_BE_USED_AS_DECISIVE_SOURCE"),
    ("AUTHZ_DENIED", "MUST_NOT_BE_USED_AS_PREMISE_OR_EVIDENCE"),
)
MODELS = {
    "C": {"model_id": "C-gemma4-unified", "repo_id": "mlx-community/gemma-4-12b-coder-fable5-composer2.5-4bit", "inference": {"temperature": 0, "max_tokens": 1024, "stream": False}},
    "N": {"model_id": "N-nail-qwen3-5-moe", "repo_id": "peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX", "inference": {"temperature": 0, "max_tokens": 1024, "stream": False}},
}

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def write_json(p, v): p.write_text(json.dumps(v, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
def get_json(url):
    with urllib.request.urlopen(url, timeout=10) as r: return json.loads(r.read())

def render(state, use):
    template = (ROOT / "prompts/AUTHORIZATION_BOUNDARY.template.txt").read_text(encoding="utf-8")
    return template.replace("{{AUTHORIZATION_STATE}}", state).replace("{{PERMITTED_USE}}", use)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default="http://127.0.0.1:8000/v1")
    ap.add_argument("--run-root", type=pathlib.Path, required=True)
    ap.add_argument("--model", choices=tuple(MODELS), required=True)
    args = ap.parse_args()
    model = MODELS[args.model]
    args.run_root.mkdir(parents=True, exist_ok=True)
    base = args.base_url.rstrip("/")
    health = get_json(base.removesuffix("/v1") + "/health")
    models = get_json(base + "/models")
    active = {x.get("id") for x in models.get("data", [])}
    if model["repo_id"] not in active:
        raise RuntimeError(f"model mismatch: expected {model['repo_id']}, got {sorted(active)}")
    write_json(args.run_root / f"RUNTIME_META-{model['model_id']}.json", {"health": health, "models": models, "selected": model})
    template_path = ROOT / "prompts/AUTHORIZATION_BOUNDARY.template.txt"
    for state, use in STATES:
        cell = args.run_root / model["model_id"] / state
        cell.mkdir(parents=True, exist_ok=True)
        prompt = render(state, use)
        prompt_path = cell / "prompt.txt"
        prompt_path.write_text(prompt, encoding="utf-8")
        payload = {"messages": [{"role": "user", "content": prompt}], "model": model["repo_id"], **model["inference"]}
        write_json(cell / "request.json", payload)
        req = urllib.request.Request(base + "/chat/completions", data=json.dumps(payload, ensure_ascii=False).encode(), headers={"Content-Type": "application/json"}, method="POST")
        started = time.time()
        try:
            with urllib.request.urlopen(req, timeout=300) as r: status, raw = r.status, r.read()
        except urllib.error.HTTPError as e: status, raw = e.code, e.read()
        elapsed = round(time.time() - started, 6)
        (cell / "response.raw.json").write_bytes(raw)
        try: response = json.loads(raw)
        except json.JSONDecodeError: response = {"_undecoded": raw.decode("utf-8", errors="replace")}
        write_json(cell / "response.json", response)
        choices = response.get("choices", []) if isinstance(response, dict) else []
        content = choices[0].get("message", {}).get("content") if choices and isinstance(choices[0], dict) else None
        (cell / "final-answer.txt").write_text(content or "", encoding="utf-8")
        write_json(cell / "RUN_RECORD.json", {
            "model_id": model["model_id"], "repo_id": model["repo_id"], "authz_state": state,
            "http_status": status, "elapsed_seconds": elapsed,
            "template_sha256": sha(template_path), "prompt_sha256": sha(prompt_path),
            "request_sha256": sha(cell / "request.json"), "response_sha256": sha(cell / "response.raw.json"),
            "created_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        })
        if status != 200: raise RuntimeError(f"{model['model_id']}/{state}: HTTP {status}")
        print(json.dumps({"model": model["model_id"], "state": state, "status": status, "elapsed": elapsed}))

if __name__ == "__main__": main()
