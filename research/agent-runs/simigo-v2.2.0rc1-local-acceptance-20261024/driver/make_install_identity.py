"""Record the installed RC bundle identity from disk.

Writes evidence/m3_install_identity.json. The aggregate bundle digest recipe is
stated in the record (`bundle_tree_digest_algorithm`) so M5 can reproduce it
exactly instead of guessing: sha256 over "<relpath>\\0<bytes>\\0<sha256>\\n" for
every file, walked in sorted order.
"""
import hashlib, json, os, subprocess, sys, time

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(B, "install/SimiGo.app")
DMG = os.path.join(B, "install/SimiGo-v2.2.0rc1.dmg")


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()


def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, (p.stdout + p.stderr).strip()


def plist(key):
    _, out = run(["/usr/libexec/PlistBuddy", "-c", "Print :" + key,
                  os.path.join(APP, "Contents/Info.plist")])
    return out


files = []
for root, dirs, names in os.walk(APP):
    dirs.sort()
    for fn in sorted(names):
        fp = os.path.join(root, fn)
        files.append({"path": os.path.relpath(fp, APP),
                      "bytes": os.path.getsize(fp),
                      "sha256": sha(fp)})

tree = hashlib.sha256()
for r in files:
    tree.update(("%s\0%d\0%s\n" % (r["path"], r["bytes"], r["sha256"])).encode())

exe = os.path.join(APP, "Contents/MacOS/SimiGo")
_, uuid_out = run(["dwarfdump", "--uuid", exe])
uuid = next((t for t in uuid_out.split() if len(t) == 36 and t.count("-") == 4), "")
_, cs_dv = run(["codesign", "-dv", "--verbose=2", APP])
_, cs_verify = run(["codesign", "--verify", "--strict", "--verbose=2", APP])
_, spctl = run(["spctl", "-a", "-vv", APP])

doc = {
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "install_path": APP,
    "source_dmg": DMG,
    "bundle_id": plist("CFBundleIdentifier"),
    "marketing_version": plist("CFBundleShortVersionString"),
    "build_version": plist("CFBundleVersion"),
    "executable_sha256": sha(exe),
    "executable_bytes": os.path.getsize(exe),
    "executable_uuid": uuid,
    "info_plist_sha256": sha(os.path.join(APP, "Contents/Info.plist")),
    "bundle_file_count": len(files),
    "bundle_tree_sha256": tree.hexdigest(),
    "bundle_tree_digest_algorithm":
        "sha256 over concat('<relpath>\\0<bytes>\\0<sha256>\\n'), files walked in sorted order",
    "codesign_dv": cs_dv,
    "codesign_verify": cs_verify,
    "spctl_assess": spctl,
    "dmg_sha256": sha(DMG) if os.path.exists(DMG) else "",
    "files": files,
}
out = os.path.join(B, "evidence/m3_install_identity.json")
json.dump(doc, open(out, "w"), indent=1, sort_keys=True)
print("wrote", out)
print("exe_sha256      =", doc["executable_sha256"])
print("exe_uuid        =", doc["executable_uuid"])
print("dmg_sha256      =", doc["dmg_sha256"])
print("bundle_tree     =", doc["bundle_tree_sha256"])
print("bundle_files    =", doc["bundle_file_count"])
print("version         =", doc["marketing_version"], doc["build_version"])
