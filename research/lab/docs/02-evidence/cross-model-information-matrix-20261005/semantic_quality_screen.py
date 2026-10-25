#!/usr/bin/env python3
"""Mechanical usability screen for partial cross-model raw outputs."""

import collections
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent
RUN = ROOT / "runs/20261005-002800-crossmodel"
SAMPLES = ("S1-release-config", "S2-version-diff", "S3-column-unit-audit", "S4-arithmetic-anomaly-audit")
MODELS = ("A-qwen3-moe", "B-qwen3-next", "C-gemma4-unified", "D-muse-glimmer")

def screen(text):
    words = re.findall(r"[A-Za-z\u4e00-\u9fff]+", text)
    top = collections.Counter(words).most_common(1)
    ratio = round(top[0][1] / len(words), 4) if words else 1.0
    unique = len(set(words))
    degenerate = ratio >= 0.5 or unique <= 10
    return {
        "word_count": len(words),
        "unique_words": unique,
        "top_word": top[0][0] if top else "",
        "top_word_ratio": ratio,
        "semantic_status": "DEGENERATE_REPETITION_EXCLUDED" if degenerate else "USABLE_FOR_SEMANTIC_NORMALIZATION",
    }

rows = []
for sample in SAMPLES:
    for model in MODELS:
        cell = RUN / sample / model
        answer = cell / "final-answer.txt"
        row = {"sample_id": sample, "model_id": model}
        if not answer.exists():
            failure = cell / "RUN_RECORD.attempt1.failed.json"
            row["raw_status"] = "HTTP_TIMEOUT"
            if failure.exists():
                row.update(json.loads(failure.read_text()))
            row.update(screen(""))
            row["semantic_status"] = "EXCLUDED_RUNTIME_UNAVAILABLE"
        else:
            row["raw_status"] = "HTTP_200"
            row.update(screen(answer.read_text()))
        rows.append(row)

out = ROOT / "semantic/QUALITY_SCREEN.json"
out.write_text(json.dumps({"screen": "top-word degeneracy screen", "rows": rows}, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({"usable": sum(r["semantic_status"].startswith("USABLE") for r in rows), "out": str(out)}))
