#!/usr/bin/env python3
"""Pin the identity of this batch's installed candidate.

Records: bundle tree digest, executable digest, bundle id + versions, bundle
signature (codesign -dv --verbose=4), Gatekeeper assessment, every Mach-O in the
bundle with its digest and install name, and the main executable's linked
dylibs. The release build product is hashed too, so "installed == built" is a
checked fact rather than an assumption.
"""
import hashlib
import json
import os
import subprocess
import sys

B2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(B2, "install", "SimiGo.app")
BUILT = os.path.join(B2, "build", "Build", "Products", "Release", "SimiGo.app")
BIN = os.path.join(APP, "Contents", "MacOS", "SimiGo")


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()


def tree_digest(root):
    rows = []
    for base, dirs, files in os.walk(root):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(base, name)
            rel = os.path.relpath(path, root)
            rows.append("%s\0%d\0%s" % (rel, os.path.getsize(path), sha(path)))
    return hashlib.sha256("\n".join(rows).encode()).hexdigest(), len(rows)


def run(*args):
    proc = subprocess.run(args, capture_output=True, text=True)
    return {"rc": proc.returncode, "out": proc.stdout.strip(), "err": proc.stderr.strip()}


def plist(key):
    proc = subprocess.run(["/usr/libexec/PlistBuddy", "-c", "Print :" + key,
                           os.path.join(APP, "Contents", "Info.plist")],
                          capture_output=True, text=True)
    return proc.stdout.strip() if proc.returncode == 0 else None


def machos(root):
    rows = []
    for base, dirs, files in os.walk(root):
        for name in files:
            path = os.path.join(base, name)
            rel = os.path.relpath(path, root)
            if rel.startswith("Contents/MacOS") or "/Frameworks/" in rel or rel.endswith(".dylib"):
                kind = subprocess.run(["file", "-b", path], capture_output=True, text=True).stdout.strip()
                if "Mach-O" in kind:
                    rows.append({"path": rel, "sha256": sha(path), "file": kind,
                                 "install_name": subprocess.run(
                                     ["otool", "-D", path], capture_output=True, text=True
                                 ).stdout.strip().splitlines()[-1] if rel.endswith(".dylib") else None})
    return sorted(rows, key=lambda r: r["path"])


def main():
    tree, count = tree_digest(APP)
    built_tree, built_count = tree_digest(BUILT)
    doc = {
        "app": APP,
        "bundle_tree_sha256": tree,
        "bundle_file_count": count,
        "release_product": BUILT,
        "release_product_tree_sha256": built_tree,
        "release_product_file_count": built_count,
        "installed_equals_built": tree == built_tree,
        "executable": BIN,
        "executable_sha256": sha(BIN),
        "executable_size": os.path.getsize(BIN),
        "bundle_id": plist("CFBundleIdentifier"),
        "marketing_version": plist("CFBundleShortVersionString"),
        "build_version": plist("CFBundleVersion"),
        "codesign_dv": run("codesign", "-dv", "--verbose=4", APP),
        "codesign_verify": run("codesign", "--verify", "--deep", "--strict", "--verbose=2", APP),
        "spctl_assess": run("spctl", "-a", "-vv", APP),
        "gatekeeper_assess_raw_expected_rejected": True,
        "macho_members": machos(APP),
        "main_executable_libraries": subprocess.run(
            ["otool", "-L", BIN], capture_output=True, text=True).stdout.strip().splitlines()[1:],
    }
    out = os.path.join(B2, "evidence", "install_identity_new_candidate.json")
    with open(out, "w") as fh:
        json.dump(doc, fh, indent=1, sort_keys=True)
    print(json.dumps({k: doc[k] for k in (
        "bundle_tree_sha256", "bundle_file_count", "installed_equals_built",
        "executable_sha256", "executable_size", "bundle_id", "marketing_version",
        "build_version")}, indent=1))
    print("codesign rc=%s verify rc=%s spctl rc=%s" % (
        doc["codesign_dv"]["rc"], doc["codesign_verify"]["rc"], doc["spctl_assess"]["rc"]))
    print("macho members:", len(doc["macho_members"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
