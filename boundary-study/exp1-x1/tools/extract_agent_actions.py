#!/usr/bin/env python3
"""EXP1-X1 recorder instrument: extract a subagent's action chain from its
model-I/O JSONL transcript. Committed BEFORE B's run (instrumentation-before-
observation). Prints one line per assistant turn: tool calls (name + truncated
key inputs) and text. Never prints full payloads."""
import json
import sys

def trunc(s, n=110):
    s = " ".join(str(s).split())
    return s[:n] + ("…" if len(s) > n else "")

def main(path):
    with open(path) as fh:
        for i, line in enumerate(fh, 1):
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            resp = d.get("response") or {}
            calls = resp.get("toolCalls") or []
            text = resp.get("text") or ""
            ts = d.get("startedAt", "")[:19]
            if not calls and not text.strip():
                continue
            print(f"--- turn {i} @ {ts}")
            for c in calls:
                name = c.get("toolName") or c.get("name") or "?"
                args = c.get("input") or c.get("arguments") or {}
                brief = {}
                for k in ("command", "file_path", "path", "pattern", "description", "prompt", "url"):
                    if k in args:
                        brief[k] = trunc(args[k], 90)
                print(f"  TOOL {name}: {brief}")
            if text.strip():
                print(f"  TEXT {trunc(text, 200)}")

if __name__ == "__main__":
    main(sys.argv[1])
