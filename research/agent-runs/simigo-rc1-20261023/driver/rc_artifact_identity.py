#!/usr/bin/env python3
"""Record the byte identity of the RC artifact bundle at a given phase.

The RC claim under test is: ONE artifact is built, tested and experimented on.
That is only checkable if the bundle digest is captured at each phase.
"""
import hashlib, json, os, subprocess, sys, time

RC = "/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023"
APP = os.environ.get("RC_APP") or os.path.join(RC, "derived/Build/Products/Debug/SimiGo.app")


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


def uuid(p):
    try:
        out = subprocess.run(["dwarfdump", "--uuid", p], capture_output=True, text=True).stdout
        for ln in out.splitlines():
            if "UUID:" in ln:
                return ln.split()[1]
    except Exception:
        return None
    return None


def main():
    phase = sys.argv[1] if len(sys.argv) > 1 else "post-build"
    files = []
    root = os.path.join(APP, "Contents")
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for fn in sorted(filenames):
            fp = os.path.join(dirpath, fn)
            if os.path.islink(fp):
                continue
            rel = os.path.relpath(fp, root)
            st = os.stat(fp)
            files.append({"rel": rel, "bytes": st.st_size, "mtime_ns": st.st_mtime_ns,
                          "sha256": sha(fp)})
    tree = hashlib.sha256(json.dumps(
        [[f["rel"], f["bytes"], f["sha256"]] for f in sorted(files, key=lambda x: x["rel"])],
        sort_keys=True).encode()).hexdigest()
    key = {}
    for img in ("SimiGo", "SimiGo.debug.dylib", "__preview.dylib"):
        p = os.path.join(root, "MacOS", img)
        if os.path.exists(p):
            key[img] = {"sha256": sha(p), "bytes": os.path.getsize(p), "uuid": uuid(p),
                        "mtime": time.strftime("%FT%T", time.localtime(os.path.getmtime(p)))}
    fw = os.path.join(root, "Frameworks")
    fw_bytes = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(fw) for f in fs) if os.path.isdir(fw) else 0
    out = {"phase": phase, "captured_at": time.strftime("%FT%T%z"),
           "app_bundle": APP, "bundle_tree_sha256": tree, "files_in_bundle": len(files),
           "key_binaries": key, "frameworks_bytes": fw_bytes,
           "xctestrun": None}
    xr = os.environ.get("RC_XCTESTRUN") or os.path.join(RC, "derived/Build/Products/SimiGo_SimiGo_macosx27.0-arm64.xctestrun")
    if os.path.exists(xr):
        out["xctestrun"] = {"path": xr, "sha256": sha(xr), "bytes": os.path.getsize(xr)}
    with open(os.path.join(RC, "artifact_identity_%s.json" % phase), "w") as f:
        json.dump(out, f, indent=1)
        f.write("\n")
    print(json.dumps({"phase": phase, "bundle_tree_sha256": tree, "files": len(files),
                      "dylib_sha256": key.get("SimiGo.debug.dylib", {}).get("sha256"),
                      "dylib_uuid": key.get("SimiGo.debug.dylib", {}).get("uuid"),
                      "dylib_bytes": key.get("SimiGo.debug.dylib", {}).get("bytes"),
                      "frameworks_bytes": fw_bytes}, indent=1))


if __name__ == "__main__":
    main()
