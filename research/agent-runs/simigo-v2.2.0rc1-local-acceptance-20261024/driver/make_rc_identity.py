"""Compose RC_MODEL_IDENTITY.json and RC_IDENTITY.json for this round.

Everything is derived: the model identity comes from RC_SOURCE_FREEZE.json
(recomputed file-by-file in this round, never reused from history), the bundle
identity from evidence/m3_install_identity.json, the dependency set from every
Package.resolved on disk, and the toolchain from the tools themselves.
"""
import hashlib, json, os, subprocess, sys, time

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "/Users/mr.simi/Documents/SimiGo"


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 22), b""):
            h.update(c)
    return h.hexdigest()


def run(cmd, cwd=None):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return (p.stdout + p.stderr).strip()


fz = json.load(open(os.path.join(B, "RC_SOURCE_FREEZE.json")))
ii = json.load(open(os.path.join(B, "evidence/m3_install_identity.json")))
now = time.strftime("%Y-%m-%dT%H:%M:%S%z")

# ------------------------------------------------------------------ model
m = fz["model"]
tok_names = ("tokenizer.json", "tokenizer_config.json", "vocab.json", "merges.txt",
             "special_tokens_map.json", "added_tokens.json")
tok = {k: v["sha256"] for k, v in m["files"].items() if k in tok_names}
model_doc = {
    "generated_at": now,
    "derived_from": "RC_SOURCE_FREEZE.json",
    "reused_from_history": False,
    "note": "File digests were recomputed from the on-disk snapshot in this round; no "
            "historical RC1 model identity was reused.",
    "repo_id": m.get("repo_id"),
    "revision": m.get("revision"),
    "snapshot_path": m.get("snapshot_path"),
    "file_count": m.get("file_count"),
    "files": m["files"],
    "tokenizer_digests": tok,
}
json.dump(model_doc, open(os.path.join(B, "RC_MODEL_IDENTITY.json"), "w"), indent=1, sort_keys=True)

# ----------------------------------------------------------- dependencies
resolved = {}
resolved_files = []
for root, dirs, files in os.walk(REPO):
    if "/.git" in root or "/build" in root or "/.build" in root:
        continue
    for fn in files:
        if fn != "Package.resolved":
            continue
        p = os.path.join(root, fn)
        rel = os.path.relpath(p, REPO)
        resolved_files.append({"path": rel, "sha256": sha(p)})
        try:
            d = json.load(open(p))
        except ValueError:
            continue
        pins = d.get("pins") or d.get("object", {}).get("pins") or []
        for pin in pins:
            name = pin.get("identity") or pin.get("package") or ""
            st = pin.get("state", {})
            resolved[name] = {"version": st.get("version"), "revision": st.get("revision")}

declared = []
for pkg in ("Packages/SimiGoRuntime/Package.swift",):
    p = os.path.join(REPO, pkg)
    if not os.path.exists(p):
        continue
    txt = open(p).read()
    import re
    for url, rev in re.findall(r'url:\s*"([^"]+)"[^)]*?revision:\s*"([0-9a-f]{40})"', txt, re.S):
        declared.append({"repo": url, "requirement": "revision " + rev, "declared_in": pkg})
    for url, ver in re.findall(r'url:\s*"([^"]+)"[^)]*?from:\s*"([^"]+)"', txt, re.S):
        declared.append({"repo": url, "requirement": "from " + ver, "declared_in": pkg})

# --------------------------------------------------------------- identity
build_log = os.path.join(B, "logs/release_build.log")
rc_doc = {
    "candidate": "v2.2.0rc1",
    "generated_at": now,
    "source": {
        "product_repo": REPO,
        "head": fz["product"]["head"],
        "branch": fz["product"]["branch"],
        "changed_file_count": fz["product"]["changed_file_count"],
        "changed_file_digests": fz["product"]["changed_file_digests"],
        "source_freeze": "RC_SOURCE_FREEZE.json",
        "lab": fz.get("lab", {}),
    },
    "build": {
        "command": "xcodebuild -project SimiGo.xcodeproj -scheme SimiGo -configuration Release "
                   "-derivedDataPath build/release-v2.1 build",
        "log": build_log,
        "log_sha256": sha(build_log) if os.path.exists(build_log) else "",
        "succeeded": "** BUILD SUCCEEDED **" in open(build_log, errors="replace").read()
        if os.path.exists(build_log) else False,
        "package_command": "bash tools/package_dmg.sh 2.2.0rc1",
    },
    "version": {"marketing_version": ii["marketing_version"],
                "build_version": ii["build_version"],
                "candidate_label": "v2.2.0rc1"},
    "bundle": {
        "install_path": ii["install_path"],
        "exe_path": os.path.join(ii["install_path"], "Contents/MacOS/SimiGo"),
        "executable_sha256": ii["executable_sha256"],
        "executable_bytes": ii["executable_bytes"],
        "executable_uuid": ii["executable_uuid"],
        "info_plist_sha256": ii["info_plist_sha256"],
        "bundle_file_count": ii["bundle_file_count"],
        "bundle_tree_sha256_recorded": ii["bundle_tree_sha256"],
        "bundle_tree_digest_algorithm": ii["bundle_tree_digest_algorithm"],
        "bundle_id": ii["bundle_id"],
        "codesign_verify": ii["codesign_verify"],
        "spctl_assess": ii["spctl_assess"],
        "dmg_sha256": ii["dmg_sha256"],
        "source_dmg": ii["source_dmg"],
    },
    "dependencies": {"declared": declared, "resolved": dict(sorted(resolved.items())),
                     "resolved_files": resolved_files},
    "toolchain": fz.get("toolchain"),
    "model": {"repo_id": m.get("repo_id"), "revision": m.get("revision"),
              "file_count": m.get("file_count"), "identity_file": "RC_MODEL_IDENTITY.json"},
    "disclaimer": "This is a local, side-loaded candidate: it is not notarized and is "
                  "rejected by Gatekeeper. Build artefacts, test artefacts and the "
                  "installed bundle are recorded separately on purpose.",
}
json.dump(rc_doc, open(os.path.join(B, "RC_IDENTITY.json"), "w"), indent=1, sort_keys=True)
print("wrote RC_MODEL_IDENTITY.json and RC_IDENTITY.json")
print("model files:", model_doc["file_count"], "revision:", model_doc["revision"])
print("exe:", rc_doc["bundle"]["executable_sha256"][:16], "build_ok:", rc_doc["build"]["succeeded"])
print("resolved packages:", len(resolved), "declared:", len(declared))
