#!/usr/bin/env python3
"""Regenerate an App-test xctestrun with the three SimiGo roots redirected.

Why this exists: `SimiGoTests` resolves the managed root to the real `~/.simigo`
(IS WAL/SHM, prefix pool, branch checkpoints, `logs/native_mlx_trace.log`) unless
the roots are overridden. Only a run with all three roots pointing into a fresh
isolation root is evidence about the suite; anything else writes user state.

Reproducibility: the isolated document is re-derived from the build's own file and
BOTH documents are re-read and diffed leaf by leaf, so "only the three injected
keys changed" is a measurement (`other_differences`), not a claim.

Placement: `__TESTROOT__` inside an xctestrun resolves relative to the xctestrun's
own directory. The isolated copy is therefore written NEXT TO the original; a copy
anywhere else would point the test host at a non-existent bundle and "pass" by
testing nothing. `--out` outside the base's directory is rejected.

usage:
  make_isolated_xctestrun.py --app <.../Debug/SimiGo.app> --isolation-root <dir>
      [--base-xctestrun PATH] [--out PATH] [--record PATH]

exit: 0 ok · 2 unexpected plist differences · 3 unusable input
"""
import argparse, glob, hashlib, json, os, plistlib, sys, time

INJECT_ROOTS = ("SIMIGO_HOME", "SIMIGO_CACHE_ROOT", "SIMIGO_STATE_GRAPH_STORE")
ISOLATED_BASENAME = "xctestrun_isolated.xctestrun"


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


def flatten(node, path=""):
    if isinstance(node, dict):
        for k in sorted(node):
            yield from flatten(node[k], "%s/%s" % (path, k))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from flatten(v, "%s[%d]" % (path, i))
    else:
        yield path, node


def targets(doc):
    out = []
    for ci, conf in enumerate(doc.get("TestConfigurations", [])):
        for ti, tgt in enumerate(conf.get("TestTargets", [])):
            out.append(((ci, ti), tgt))
    return out


def die(msg, code=3):
    sys.stderr.write("make_isolated_xctestrun: %s\n" % msg)
    sys.exit(code)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", required=True)
    ap.add_argument("--isolation-root", required=True)
    ap.add_argument("--base-xctestrun")
    ap.add_argument("--out")
    ap.add_argument("--record")
    a = ap.parse_args()

    app = os.path.abspath(a.app)
    iso = os.path.abspath(a.isolation_root)
    if not os.path.isdir(app):
        die("app bundle missing: %s" % app)
    if not os.path.isfile(os.path.join(app, "Contents/MacOS/SimiGo")):
        die("not a SimiGo.app test host: %s" % app)
    if not os.path.isdir(iso):
        die("isolation root missing: %s" % iso)

    products = os.path.dirname(os.path.dirname(app))          # .../Build/Products
    if a.base_xctestrun:
        base_xr = os.path.abspath(a.base_xctestrun)
        if not os.path.isfile(base_xr):
            die("base xctestrun missing: %s" % base_xr)
    else:
        found = [p for p in sorted(glob.glob(os.path.join(products, "*.xctestrun")))
                 if os.path.basename(p) != ISOLATED_BASENAME]
        if len(found) != 1:
            die("cannot pick a base xctestrun (%d candidates in %s); pass --base-xctestrun"
                % (len(found), products))
        base_xr = found[0]

    out = os.path.abspath(a.out) if a.out else os.path.join(products, ISOLATED_BASENAME)
    if os.path.dirname(out) != os.path.dirname(base_xr):
        die("--out must sit beside the base xctestrun (__TESTROOT__ resolves there)")

    env = {
        "SIMIGO_HOME": os.path.join(iso, "home"),
        "SIMIGO_CACHE_ROOT": os.path.join(iso, "cache"),
        "SIMIGO_STATE_GRAPH_STORE": os.path.join(iso, "state-graph", "reference-graph-v1.json"),
    }
    for key, val in env.items():
        if not os.path.isabs(val) or os.path.commonpath([os.path.abspath(val), iso]) != iso:
            die("%s resolves outside the isolation root: %s" % (key, val))

    doc = plistlib.load(open(base_xr, "rb"))
    base = {p: v for p, v in flatten(doc)}
    touched = 0
    for _, tgt in targets(doc):
        ev = dict(tgt.get("EnvironmentVariables") or {})
        ev.update(env)
        tgt["EnvironmentVariables"] = ev
        touched += 1
    if touched == 0:
        die("no TestTargets in %s" % base_xr)

    with open(out, "wb") as f:
        plistlib.dump(doc, f, fmt=plistlib.FMT_XML, sort_keys=True)

    got = {p: v for p, v in flatten(plistlib.load(open(out, "rb")))}
    added = {p: v for p, v in got.items() if p not in base}
    removed = {p: v for p, v in base.items() if p not in got}
    changed = {p: {"a": base[p], "b": got[p]} for p in base if p in got and base[p] != got[p]}
    unexpected = {
        "added": {p: v for p, v in added.items() if not any(p.endswith("/" + k) for k in INJECT_ROOTS)},
        "removed": removed,
        "changed": changed,
    }
    other = [d for d in (unexpected["added"], removed, changed) if d]

    rec = {
        "source_xctestrun": base_xr,
        "source_sha256": sha(base_xr),
        "isolated_xctestrun": out,
        "isolated_sha256": sha(out),
        "test_targets_patched": touched,
        "environment_before": {p.rsplit("/", 1)[-1]: v for p, v in base.items()
                               if "/EnvironmentVariables/" in p},
        "injected_keys": env,
        "other_differences": other,
        "placement_note": "__TESTROOT__ resolves relative to the xctestrun's directory;"
                          " the isolated copy must stay beside the original.",
        "generated_at": time.strftime("%FT%T%z"),
    }
    if a.record:
        rec_path = os.path.abspath(a.record)
        if not os.path.isdir(os.path.dirname(rec_path)):
            die("--record directory missing: %s" % os.path.dirname(rec_path))
        with open(rec_path, "w") as f:
            json.dump(rec, f, indent=1)
            f.write("\n")
    print(json.dumps({"isolated": out, "sha256": rec["isolated_sha256"],
                      "targets": touched, "other_differences": other}, indent=1))
    if other:
        sys.stderr.write("make_isolated_xctestrun: plist changed beyond the three roots\n")
        sys.exit(2)


if __name__ == "__main__":
    main()
