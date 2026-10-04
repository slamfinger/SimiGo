#!/usr/bin/env python3
"""Run frozen CI-C own-structure arms on the two usable models only."""

import argparse
import datetime
import hashlib
import json
import pathlib
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent
ARMS = ("FULL", "K1_ONLY", "K2_ONLY", "GAMMA_REDUCED", "K3_DELETED", "K3_PRECOMPUTED_F", "ID_BINDING_BROKEN")
MODELS = {
    "A": {
        "model_id": "A-qwen3-moe",
        "repo_id": "mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit",
        "inference": {"temperature": 0, "max_tokens": 1024, "stream": False},
    },
    "C": {
        "model_id": "C-gemma4-unified",
        "repo_id": "mlx-community/gemma-4-12b-coder-fable5-composer2.5-4bit",
        "inference": {"temperature": 0, "max_tokens": 1024, "stream": False},
    },
    "N": {
        "model_id": "N-nail-qwen3-5-moe",
        "repo_id": "peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX",
        "inference": {"temperature": 0, "max_tokens": 1024, "stream": False},
    },
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def get_json(url):
    with urllib.request.urlopen(url, timeout=10) as response:
        return json.loads(response.read())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8000/v1")
    parser.add_argument("--run-root", type=pathlib.Path, required=True)
    parser.add_argument("--model", choices=tuple(MODELS), required=True)
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()

    model = MODELS[args.model]
    if args.run_root.exists() and not args.resume:
        raise RuntimeError(f"run root exists: {args.run_root}")
    args.run_root.mkdir(parents=True, exist_ok=True)

    health = get_json(args.base_url.rstrip("/").removesuffix("/v1") + "/health")
    models = get_json(args.base_url.rstrip("/") + "/models")
    active_ids = {x.get("id") for x in models.get("data", [])}
    if model["repo_id"] not in active_ids:
        raise RuntimeError(f"loaded model mismatch; expected {model['repo_id']}, got {sorted(active_ids)}")
    (args.run_root / "RUNTIME_META.json").write_text(
        json.dumps({"health": health, "models": models, "selected": model}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    for arm in ARMS:
        cell = args.run_root / model["model_id"] / arm
        done = cell / "RUN_RECORD.json"
        if args.resume and done.exists() and json.loads(done.read_text()).get("http_status") == 200:
            continue
        cell.mkdir(parents=True, exist_ok=True)
        prompt_path = ROOT / "prompts" / f"{arm}.prompt.txt"
        prompt = prompt_path.read_text(encoding="utf-8")
        payload = {
            "messages": [{"role": "user", "content": prompt}],
            "model": model["repo_id"],
            **model["inference"],
        }
        write_json(cell / "request.json", payload)
        request = urllib.request.Request(
            args.base_url.rstrip("/") + "/chat/completions",
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        started = time.time()
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                status, raw = response.status, response.read()
        except urllib.error.HTTPError as exc:
            status, raw = exc.code, exc.read()
        elapsed = round(time.time() - started, 6)
        (cell / "response.raw.json").write_bytes(raw)
        try:
            response_json = json.loads(raw)
        except json.JSONDecodeError:
            response_json = {"_undecoded": raw.decode("utf-8", errors="replace")}
        write_json(cell / "response.json", response_json)
        choices = response_json.get("choices", []) if isinstance(response_json, dict) else []
        content = choices[0].get("message", {}).get("content") if choices and isinstance(choices[0], dict) else None
        (cell / "final-answer.txt").write_text(content or "", encoding="utf-8")
        write_json(cell / "RUN_RECORD.json", {
            "arm": arm,
            "model_id": model["model_id"],
            "repo_id": model["repo_id"],
            "http_status": status,
            "elapsed_seconds": elapsed,
            "prompt_sha256": sha(prompt_path),
            "request_sha256": sha(cell / "request.json"),
            "response_sha256": sha(cell / "response.raw.json"),
            "created_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        })
        if status != 200:
            raise RuntimeError(f"{arm}: HTTP {status}")
        print(json.dumps({"arm": arm, "model": model["model_id"], "status": status, "elapsed": elapsed}))


if __name__ == "__main__":
    main()
