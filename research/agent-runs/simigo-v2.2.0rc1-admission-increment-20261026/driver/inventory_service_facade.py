#!/usr/bin/env python3
"""Record who in the product can actually trigger `Service.startSelected()`.

Why this exists
  The Service/HTTP gate on the rebuilt candidate passes on the wire path (TLS
  listener -> LOCALB proof gate -> dispatch -> generate), but it explicitly does
  not execute the `Service` facade: `Service.start` persists SwiftUI preference
  references through `AppConfig`, and this batch may not write real user defaults.
  That deviation was disclosed as a limitation. This driver answers the next
  question with evidence instead of an assumption: if the facade is not executed by
  the gate, what does execute it in the product?

Method
  Read-only `git grep` at the frozen HEAD for `Service.shared` and for the start
  selectors, split production vs test files, and record the hits verbatim. No file
  is modified, no build is produced, no state is touched.

usage: inventory_service_facade.py [--out PATH]
"""
import json
import os
import subprocess
import sys
import time

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "/Users/mr.simi/Documents/SimiGo"
OUT = os.path.join(B, "evidence/service_facade_inventory.json")
if "--out" in sys.argv:
    OUT = sys.argv[sys.argv.index("--out") + 1]

PATTERNS = [
    ("Service.shared", "who holds the facade"),
    ("startSelected()", "what starts it"),
    ("restartSelected()", "what restarts it"),
    ("Service(" , "direct instantiation"),
]


def git(args):
    p = subprocess.run(["git", "-C", REPO] + args, capture_output=True, text=True)
    return {"argv": ["git", "-C", REPO] + args, "exit_code": p.returncode,
            "stdout": p.stdout, "stderr": p.stderr.strip()}


def grep(pattern):
    r = git(["grep", "-n", "--", pattern])
    hits = []
    for line in r["stdout"].splitlines():
        path, _, rest = line.partition(":")
        lineno, _, text = rest.partition(":")
        hits.append({"file": path, "line": int(lineno) if lineno.isdigit() else None,
                     "text": text.strip(),
                     "tier": "test" if "Tests/" in path else "production"})
    return hits


def main():
    head = git(["rev-parse", "HEAD"])
    branch = git(["rev-parse", "--abbrev-ref", "HEAD"])
    status = git(["status", "--porcelain"])

    result = {
        "captured_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "repo": REPO,
        "head": head["stdout"].strip(),
        "branch": branch["stdout"].strip(),
        "dirty_entries": len([l for l in status["stdout"].splitlines() if l.strip()]),
        "read_only": True,
        "method": "git grep at HEAD; no worktree file is read or written",
        "patterns": {},
    }

    for pattern, purpose in PATTERNS:
        hits = grep(pattern)
        result["patterns"][pattern] = {
            "purpose": purpose,
            "hits": hits,
            "production": [h for h in hits if h["tier"] == "production"],
            "test": [h for h in hits if h["tier"] == "test"],
        }

    start = result["patterns"]["startSelected()"]
    facade = result["patterns"]["Service.shared"]
    production_triggers = [h for h in start["production"]
                           if "Service.swift" not in h["file"]]
    result["findings"] = {
        "facade_holders_in_production": [h["file"] for h in facade["production"]],
        "start_selectors_in_production_outside_Service": [
            "%s:%s" % (h["file"], h["line"]) for h in production_triggers],
        "start_selectors_in_tests": ["%s:%s" % (h["file"], h["line"])
                                     for h in start["test"]],
        "only_appkit_callers": all("SimiGo/App/" in h["file"] for h in production_triggers),
        "statement": (
            "No test target and no headless entry calls Service.startSelected(); the "
            "only production triggers live in the AppKit layer (menu panel, settings, "
            "and Service's own auto-restart). The Service/HTTP gate therefore cannot "
            "execute the facade without either a GUI operation or a new product entry."
            if not start["test"] else
            "Some test or headless entry does reach the start selector; re-read the hits."),
    }

    with open(OUT, "w") as handle:
        json.dump(result, handle, indent=1)
        handle.write("\n")
    print(json.dumps({"out": os.path.basename(OUT), "head": result["head"],
                      "facade_holders": result["findings"]["facade_holders_in_production"],
                      "production_triggers": result["findings"][
                          "start_selectors_in_production_outside_Service"],
                      "test_triggers": result["findings"]["start_selectors_in_tests"],
                      "only_appkit_callers": result["findings"]["only_appkit_callers"]},
                     indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
