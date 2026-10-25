#!/usr/bin/env python3
"""Regenerate the isolated xctestrun used to run the App test suite off-real-home.

Why a tool instead of a hand patch: the isolation claim has to be reproducible.
run1/run3 were driven by an xctestrun that was patched once, inline. This tool
re-derives it from the build's own xctestrun, RE-READS both files and proves the
only differences are the three injected keys - the "other_differences" field is
computed by diffing the plists, never asserted by hand.

Usage: make_isolated_xctestrun.py <app_dir> <batch_dir>

<app_dir> must be <batch>/derived/Build/Products/Debug/SimiGo.app. The isolated
copy is written NEXT TO the source xctestrun on purpose: __TESTROOT__ inside the
file is resolved relative to the xctestrun's own directory, so a copy anywhere
else would point the test host at a non-existent bundle and "pass" by testing
nothing.
"""
import hashlib, json, os, plistlib, sys, time

INJECT_ROOTS = ("SIMIGO_HOME", "SIMIGO_CACHE_ROOT", "SIMIGO_STATE_GRAPH_STORE")


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


def flatten(node, path=""):
    """Yield (dotted_path, scalar) so two plists can be compared leaf by leaf."""
    if isinstance(node, dict):
        for k in sorted(node):
            yield from flatten(node[k], "%s/%s" % (path, k))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from flatten(v, "%s[%d]" % (path, i))
    else:
        yield path, node


def targets(doc):
    """Every TestTarget dict in the document, with its index path."""
    out = []
    for ci, conf in enumerate(doc.get("TestConfigurations", [])):
        for ti, tgt in enumerate(conf.get("TestTargets", [])):
            out.append(((ci, ti), tgt))
    return out


def main():
    app_dir, batch = sys.argv[1], sys.argv[2]
    products = os.path.dirname(os.path.dirname(app_dir))       # .../Build/Products
    src = os.path.join(products, "SimiGo_SimiGo_macosx27.0-arm64.xctestrun")
    dst = os.path.join(products, "xctestrun_isolated.xctestrun")
    env = {
        "SIMIGO_HOME": os.path.join(batch, "isolation/home"),
        "SIMIGO_CACHE_ROOT": os.path.join(batch, "isolation/cache"),
        "SIMIGO_STATE_GRAPH_STORE": os.path.join(batch, "isolation/state-graph/reference-graph-v1.json"),
    }

    if not os.path.isdir(app_dir):
        sys.exit("app bundle missing: %s" % app_dir)
    if not os.path.exists(src):
        sys.exit("base xctestrun missing: %s" % src)

    doc = plistlib.load(open(src, "rb"))
    base = {p: v for p, v in flatten(doc)}
    touched = 0
    for _, tgt in targets(doc):
        ev = dict(tgt.get("EnvironmentVariables") or {})
        ev.update(env)
        tgt["EnvironmentVariables"] = ev
        touched += 1
    if touched == 0:
        sys.exit("no TestTargets in %s" % src)

    with open(dst, "wb") as f:
        plistlib.dump(doc, f, fmt=plistlib.FMT_XML, sort_keys=True)

    # Re-read from disk and diff, so "nothing else changed" is measured.
    got = {p: v for p, v in flatten(plistlib.load(open(dst, "rb")))}
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
        "source_xctestrun": src,
        "source_sha256": sha(src),
        "isolated_xctestrun": dst,
        "isolated_sha256": sha(dst),
        "test_targets_patched": touched,
        # the PRE-patch environment, taken from the flattened base document, so a
        # later reader can see exactly what Xcode injects on its own.
        "environment_before": {
            p.rsplit("/", 1)[-1]: v for p, v in base.items() if "/EnvironmentVariables/" in p
        },
        "injected_keys": env,
        "other_differences": other,
        "placement_note": "__TESTROOT__ is resolved relative to the xctestrun's directory;"
                          " the isolated copy must stay beside the original or the test host"
                          " path resolves to a non-existent bundle.",
        "generated_at": time.strftime("%FT%T%z"),
    }
    out = os.path.join(batch, "xctestrun_isolation.json")
    with open(out, "w") as f:
        json.dump(rec, f, indent=1)
        f.write("\n")
    print(json.dumps({"isolated": dst, "sha256": rec["isolated_sha256"],
                      "targets": touched, "other_differences": other}, indent=1))
    if other:
        sys.exit(2)


if __name__ == "__main__":
    main()
