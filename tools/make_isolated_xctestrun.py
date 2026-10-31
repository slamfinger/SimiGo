#!/usr/bin/env python3
"""Regenerate an App-test xctestrun with the four isolated roots redirected.

Why this exists: `SimiGoTests` resolves the managed root to the real `~/.simigo`
(IS WAL/SHM, prefix pool, branch checkpoints, `logs/native_mlx_trace.log`) unless
the roots are overridden. The Qoder transcript scan root is also redirected
into that fresh isolation root, so App tests cannot tail real Qoder transcripts.

Reproducibility: the isolated document is re-derived from the build's own file and
BOTH documents are re-read and diffed leaf by leaf, so only the four root keys
and explicitly requested target opt-ins may change; `other_differences` is measured.

Placement: `__TESTROOT__` inside an xctestrun resolves relative to the xctestrun's
own directory. The isolated copy is therefore written NEXT TO the original; a copy
anywhere else would point the test host at a non-existent bundle and "pass" by
testing nothing. `--out` outside the base's directory is rejected.

usage:
  make_isolated_xctestrun.py --app <.../Debug/SimiGo.app> --isolation-root <dir>
      [--base-xctestrun PATH] [--out PATH] [--record PATH]
      [--target-env TARGET:KEY=VALUE]...

exit: 0 ok · 2 unexpected plist differences · 3 unusable input
"""
import argparse, glob, hashlib, json, os, plistlib, sys, time

INJECT_ROOTS = ("SIMIGO_HOME", "SIMIGO_CACHE_ROOT", "SIMIGO_STATE_GRAPH_STORE",
                "QODER_PROJECTS_DIR")
TARGET_ENV_ALLOWLIST = {
    "SIMIGO_PREFIX_POOL": "1",
    "SIMIGO_BRANCH_CHECKPOINTS": "1",
    "SIMIGO_REQUEST_BUDGET_MS": "0",
    "SIMIGO_KV_FREE_MATRIX": "1",
    "SIMIGO_KV_BLOCKED_ONLY": "1",
}
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


def parse_target_env(spec):
    target, sep, assignment = spec.partition(":")
    key, equals, value = assignment.partition("=")
    if not sep or not target or not equals or not key or not value:
        die("invalid --target-env %r (expected TARGET:KEY=VALUE)" % spec, 2)
    expected = TARGET_ENV_ALLOWLIST.get(key)
    if expected is None or value != expected:
        allowed = ", ".join("%s=%s" % item for item in TARGET_ENV_ALLOWLIST.items())
        die("unsupported --target-env %s=%s; allowed: %s" % (key, value, allowed), 2)
    return target, key, value


def target_name(tgt):
    for key in ("BlueprintName", "TestTargetName", "TargetName"):
        value = tgt.get(key)
        if isinstance(value, str) and value:
            return value
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", required=True)
    ap.add_argument("--isolation-root", required=True)
    ap.add_argument("--base-xctestrun")
    ap.add_argument("--out")
    ap.add_argument("--record")
    ap.add_argument("--target-env", action="append", default=[],
                    metavar="TARGET:KEY=VALUE",
                    help="opt one XCTest target into a narrowly allowlisted test mode")
    a = ap.parse_args()

    requested_target_env = {}
    for spec in a.target_env:
        target, key, value = parse_target_env(spec)
        existing = requested_target_env.setdefault(target, {})
        if key in existing and existing[key] != value:
            die("conflicting --target-env values for %s/%s" % (target, key), 2)
        existing[key] = value

    for target, settings in requested_target_env.items():
        if (settings.get("SIMIGO_KV_FREE_MATRIX") == "1"
                and settings.get("SIMIGO_KV_BLOCKED_ONLY") == "1"):
            die("KV-free matrix modes are mutually exclusive for target %s" % target, 2)

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
        "QODER_PROJECTS_DIR": os.path.join(iso, "qoder-projects"),
    }
    for key, val in env.items():
        if not os.path.isabs(val) or os.path.commonpath([os.path.abspath(val), iso]) != iso:
            die("%s resolves outside the isolation root: %s" % (key, val))

    try:
        with open(base_xr, "rb") as f:
            doc = plistlib.load(f)
    except Exception as exc:                                  # noqa: BLE001
        die("base xctestrun is not a readable plist (%s): %s" % (base_xr, exc))
    base = {p: v for p, v in flatten(doc)}
    test_targets = targets(doc)
    if not test_targets:
        die("no TestTargets in %s" % base_xr)
    available_names = {target_name(tgt) for _, tgt in test_targets}
    unknown_targets = sorted(set(requested_target_env) - available_names)
    if unknown_targets:
        present = ", ".join(sorted(n for n in available_names if n))
        die("--target-env target not found: %s (available: %s)" %
            (", ".join(unknown_targets), present), 2)

    touched = 0
    applied_target_env = []
    for (ci, ti), tgt in test_targets:
        ev = dict(tgt.get("EnvironmentVariables") or {})
        for key, value in env.items():
            if key in ev and ev[key] != value:
                die("refusing to replace existing %s in target %s" %
                    (key, target_name(tgt) or "<unnamed>"))
            ev[key] = value
        name = target_name(tgt)
        for key, value in requested_target_env.get(name, {}).items():
            if key in ev and ev[key] != value:
                die("refusing to replace existing opt-in %s in target %s" % (key, name))
            ev[key] = value
            applied_target_env.append({"target": name, "key": key, "value": value,
                                       "configuration_index": ci, "target_index": ti})
        tgt["EnvironmentVariables"] = ev
        touched += 1

    with open(out, "wb") as f:
        plistlib.dump(doc, f, fmt=plistlib.FMT_XML, sort_keys=True)

    try:
        with open(out, "rb") as f:
            got = {p: v for p, v in flatten(plistlib.load(f))}
    except Exception as exc:                                  # noqa: BLE001
        die("rewritten xctestrun is not re-readable (%s): %s" % (out, exc))
    added = {p: v for p, v in got.items() if p not in base}
    removed = {p: v for p, v in base.items() if p not in got}
    changed = {p: {"a": base[p], "b": got[p]} for p in base if p in got and base[p] != got[p]}
    allowed_added_keys = set(INJECT_ROOTS) | set(TARGET_ENV_ALLOWLIST)
    unexpected = {
        "added": {p: v for p, v in added.items()
                  if not ("/EnvironmentVariables/" in p
                          and p.rsplit("/", 1)[-1] in allowed_added_keys)},
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
        "target_env_requested": requested_target_env,
        "target_env_applied": applied_target_env,
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
                      "targets": touched, "target_env_applied": applied_target_env,
                      "other_differences": other}, indent=1))
    if other:
        sys.stderr.write("make_isolated_xctestrun: plist changed beyond the four roots and requested target opt-ins\n")
        sys.exit(2)


if __name__ == "__main__":
    main()
