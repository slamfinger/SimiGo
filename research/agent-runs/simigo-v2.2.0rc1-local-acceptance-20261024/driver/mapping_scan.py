"""Recompute the Lab -> product source mapping from disk.

For every Swift file in the three product source roots, hash it and look for a
byte-identical Lab file, a same-name Lab file (diverged), or no counterpart.
Each hit is then cross-checked against `git show HEAD:<lab path>` so the report
can distinguish "matches a Lab commit" from "matches uncommitted Lab worktree
content only". Writes evidence/source_mapping_scan.json and
evidence/source_mapping_diverged.json. Exit 0 always: this is a census, not a
pass/fail gate.
"""
import hashlib, json, os, subprocess

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAB = "/Users/mr.simi/Documents/SimiGo-Lab"
PRODUCT = "/Users/mr.simi/Documents/SimiGo"
ROOTS = ["Packages/SimiGoRuntime/Sources/SimiGo2Experimental",
         "Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract",
         "SimiGo"]


def sha_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def sha_bytes(b):
    return hashlib.sha256(b).hexdigest()


def nlines(p):
    with open(p, errors="replace") as f:
        return sum(1 for _ in f)


def git(repo, *args):
    return subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True)


lab_by_sha, lab_by_name = {}, {}
for root, dirs, files in os.walk(LAB):
    if "/.git" in root or "/.build" in root or "/vendor" in root:
        continue
    for fn in files:
        if not fn.endswith(".swift"):
            continue
        p = os.path.join(root, fn)
        try:
            s = sha_file(p)
        except OSError:
            continue
        rel = os.path.relpath(p, LAB)
        lab_by_sha.setdefault(s, []).append(rel)
        lab_by_name.setdefault(fn, []).append(rel)

out = {"lab_repo": LAB, "lab_branch": git(LAB, "branch", "--show-current").stdout.strip(),
       "lab_head": git(LAB, "rev-parse", "HEAD").stdout.strip(),
       "lab_dirty_count": len(git(LAB, "status", "--porcelain").stdout.splitlines()),
       "product_repo": PRODUCT,
       "product_branch": git(PRODUCT, "branch", "--show-current").stdout.strip(),
       "product_head": git(PRODUCT, "rev-parse", "HEAD").stdout.strip(),
       "property": "lab_head_state: committed_match = product file equals the Lab HEAD blob",
       "modules": {}}

for base in ROOTS:
    rows = []
    for root, dirs, files in os.walk(os.path.join(PRODUCT, base)):
        for fn in sorted(files):
            if not fn.endswith(".swift"):
                continue
            p = os.path.join(root, fn)
            s = sha_file(p)
            r = {"product_path": os.path.relpath(p, PRODUCT), "product_sha256": s,
                 "product_lines": nlines(p)}
            if s in lab_by_sha:
                r["class"] = "IDENTICAL"
                r["lab_paths"] = sorted(lab_by_sha[s])
                lp = r["lab_paths"][0]
                blob = git(LAB, "show", "HEAD:" + lp)
                if blob.returncode != 0:
                    r["lab_head_state"] = "NOT_TRACKED_AT_HEAD"
                elif sha_bytes(blob.stdout.encode()) == s:
                    r["lab_head_state"] = "committed_match"
                else:
                    r["lab_head_state"] = "worktree_only"
            elif fn in lab_by_name:
                r["class"] = "SAME_NAME_DIVERGED"
                r["lab_candidates"] = sorted(lab_by_name[fn])
            else:
                r["class"] = "PRODUCT_ONLY"
            rows.append(r)
    out["modules"][base] = {
        "files": len(rows),
        "identical": sum(1 for r in rows if r["class"] == "IDENTICAL"),
        "committed_match": sum(1 for r in rows if r.get("lab_head_state") == "committed_match"),
        "identical_but_lab_uncommitted": sum(
            1 for r in rows if r.get("lab_head_state") in ("worktree_only", "NOT_TRACKED_AT_HEAD")),
        "diverged": sum(1 for r in rows if r["class"] == "SAME_NAME_DIVERGED"),
        "product_only": sum(1 for r in rows if r["class"] == "PRODUCT_ONLY"),
        "rows": rows,
    }

div = []
for base, v in out["modules"].items():
    for r in v["rows"]:
        if r["class"] != "SAME_NAME_DIVERGED":
            continue
        lab = r["lab_candidates"][0]
        d = subprocess.run(["diff", "-u", os.path.join(LAB, lab), os.path.join(PRODUCT, r["product_path"])],
                           capture_output=True, text=True).stdout
        added = sum(1 for l in d.splitlines() if l.startswith("+") and not l.startswith("+++"))
        removed = sum(1 for l in d.splitlines() if l.startswith("-") and not l.startswith("---"))
        div.append({"product_path": r["product_path"], "product_lines": r["product_lines"],
                    "lab_path": lab, "added": added, "removed": removed,
                    "shape": "product_trimmed" if added < removed else "product_extended"})

ev = os.path.join(B, "evidence")
json.dump(out, open(os.path.join(ev, "source_mapping_scan.json"), "w"), indent=1, sort_keys=True)
json.dump(div, open(os.path.join(ev, "source_mapping_diverged.json"), "w"), indent=1)

for base, v in out["modules"].items():
    print("%-58s files=%-3d identical=%-3d (committed_match=%-3d uncommitted_lab=%-2d) "
          "diverged=%-2d product_only=%d"
          % (base, v["files"], v["identical"], v["committed_match"],
             v["identical_but_lab_uncommitted"], v["diverged"], v["product_only"]))
for r in div:
    print("  diverged %-50s +%-4d -%-4d %s" % (r["product_path"].split("/")[-1],
                                               r["added"], r["removed"], r["shape"]))
