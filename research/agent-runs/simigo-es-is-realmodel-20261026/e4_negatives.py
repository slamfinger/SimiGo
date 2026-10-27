#!/usr/bin/env python3
"""Goal step 4: the four negative injections, through the installed product's
own HTTP routes on the real model, on a DEDICATED experiment root.

N1 missing settlement      -> /is/file, /is/object, /is/dependency for absent rows
N2 object tampering        -> index-only rows are re-read from the locator and
                              verified against the settled digest; tamper the
                              bytes, read, then RESTORE (finally)
N3 identity mismatch       -> correct relative path under the wrong root_id;
                              cross-identity KV/pool bind at the ES layer
N4 stale-settlement reuse  -> after tampering, does the ES still feed a cached
                              retrieval / IS content to the model?

Nothing here writes to ~/.simigo/simigo.sqlite3 (read-only) and nothing touches
the user's real Desktop roots.
"""
import hashlib
import json
import os
import pathlib
import sqlite3
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "http://127.0.0.1:8000"
HOME = os.path.expanduser("~")
DB = pathlib.Path(HOME) / ".simigo" / "simigo.sqlite3"
TRACE = f"{HOME}/.simigo/logs/native_mlx_trace.log"
EXP = pathlib.Path(__file__).resolve().parent
ROOT = EXP / "dep-root"
ROOT_ID = "work-000000008a721251"
ALPHA = "marker_alpha_7Q.txt"
GAMMA = "marker_gamma_4K_NEVER_SETTLED.txt"
MISSING = "marker_missing_ZZ.txt"
QUERY_ALPHA = "阿尔法-7Q 记录里三种钻机各适用什么地层？一句话。"
QUERY_TAMPER = "阿尔法-7Q 文件里的实测砂层厚度数字是多少？一句话。"
MODEL = "simigo"

KEYS = ("arrive", "prefill", "promptTokens", "cacheHitTokens", "cacheEff", "mode=",
        "poolBind", "poolExport", "poolTokenExport", "poolTokenHit",
        "poolTokenHitRejected", "poolHit", "reuseMiss", "prefixMismatch", "prefixDiff",
        "cacheSave", "RELEASED", "isKv", "admit")


def http(method, path, body=None, timeout=900):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path, data=data, method=method,
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw[:400]}
    except Exception as e:
        return -1, {"error": repr(e)}


def q(sql, params=()):
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in con.execute(sql, params).fetchall()]
    finally:
        con.close()


def sha(b):
    return hashlib.sha256(b).hexdigest()


def trace_off():
    return os.path.getsize(TRACE) if os.path.exists(TRACE) else 0


def trace_since(off):
    with open(TRACE, "rb") as f:
        f.seek(off)
        out = f.read().decode(errors="replace")
    return [ln.strip() for ln in out.splitlines() if any(k in ln for k in KEYS)]


def chat(sess, content, max_tokens=48):
    off = trace_off()
    st, body = http("POST", "/v1/chat/completions", {
        "model": MODEL, "session_id": sess, "stream": False, "temperature": 0.0,
        "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": content}]})
    msg = ((body.get("choices") or [{}])[0].get("message") or {}).get("content", "")
    return {"http": st, "usage": body.get("usage"), "answer": msg[:300],
            "error": body.get("error"), "trace": trace_since(off)}


out = {"started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
       "build": {"bundle_version": "26", "exe_sha256_prefix": "fbe416775657454c",
                 "source_head": "97043902075b67eb1693749fd6ed50421eccf3ba"},
       "model": MODEL, "steps": {}}

alpha_path = ROOT / ALPHA
original_bytes = alpha_path.read_bytes()
disk_sha = sha(original_bytes)
st0, file0 = http("GET", "/v1/simigo/is/file?root_id=" + ROOT_ID + "&path="
                  + urllib.parse.quote(ALPHA))
settled_sha = file0.get("content_sha256")
out["steps"]["preflight"] = {
    "disk_sha": disk_sha, "is_file_http": st0, "settled_sha": settled_sha,
    "object_id": file0.get("object_id"), "settled_bytes_in_db": bool(file0.get("content")),
    "match": disk_sha == settled_sha}
# SAFETY: only proceed when the disk bytes equal the settled digest, so the
# restore below returns the root to exactly the state found.
assert disk_sha == settled_sha, "experiment file already diverged from its settlement"
assert file0.get("object_id") in (None, ""), "row is not index-only; tamper test N/A"

# ---------------- N1 missing settlement ----------------
out["steps"]["N1_missing_settlement"] = {
    "file_never_seen": http("GET", "/v1/simigo/is/file?root_id=" + ROOT_ID
                            + "&path=" + MISSING),
    "file_removed_from_root": http("GET", "/v1/simigo/is/file?root_id=" + ROOT_ID
                                   + "&path=" + GAMMA),
    "object_unknown_id": http("GET", "/v1/simigo/is/object?id=" + "0" * 64),
    "object_digest_not_an_object": http("GET", "/v1/simigo/is/object?id=" + settled_sha),
    "dependency_unknown": http(
        "GET", "/v1/simigo/is/dependency?id=" + urllib.parse.quote(
            f"file:{ROOT_ID}/{MISSING}", safe=":")),
}

# ---------------- N2 object tampering ----------------
t0 = trace_off()
tampered = original_bytes + (
    "\nTAMPER 注入-请勿采信：砂层厚度被改为 99.9m，编号 ALPHA-7Q-TAMPERED。\n"
).encode()
try:
    alpha_path.write_bytes(tampered)
    out["steps"]["N2_tamper_applied"] = {
        "tampered_sha": sha(tampered),
        "size_before": len(original_bytes), "size_after": len(tampered),
        "is_file_after_tamper": http(
            "GET", "/v1/simigo/is/file?root_id=" + ROOT_ID + "&path="
            + urllib.parse.quote(ALPHA)),
        "is_object_after_tamper": http(
            "GET", "/v1/simigo/is/object?id=" + settled_sha),
        "dependency_after_tamper": http(
            "GET", "/v1/simigo/is/dependency?id=" + urllib.parse.quote(
                f"file:{ROOT_ID}/{ALPHA}", safe=":")),
        "deep_status_after_tamper": http("GET", "/v1/simigo/is/status?deep=1"),
    }
    # N4: does the ES still consume the (now unverifiable) content?
    retr_before = q("select demand_id, hit_count, status, result_object_id"
                    " from retrieval_settlements where query like ?"
                    " order by settled_at desc limit 3", ("%阿尔法-7Q%",))
    out["steps"]["N4_es_retrieval_before_es_turn"] = retr_before
    out["steps"]["N4_es_turn_settled_query"] = chat("e4-tamper-cache", QUERY_ALPHA)
    out["steps"]["N4_es_turn_fresh_query"] = chat("e4-tamper-fresh", QUERY_TAMPER)
    out["steps"]["N4_es_retrieval_after_es_turns"] = q(
        "select demand_id, hit_count, status, result_object_id"
        " from retrieval_settlements where query like ? order by settled_at desc"
        " limit 3", ("%阿尔法-7Q%",))
    out["steps"]["N4_trace_window"] = trace_since(t0)
finally:
    alpha_path.write_bytes(original_bytes)

out["steps"]["N2_after_restore"] = {
    "disk_sha_matches_settled": sha(alpha_path.read_bytes()) == settled_sha,
    "is_file_after_restore": http(
        "GET", "/v1/simigo/is/file?root_id=" + ROOT_ID + "&path="
        + urllib.parse.quote(ALPHA)),
}

# ---------------- N3 identity mismatch ----------------
other_root = q("select root_id from roots where root_id<>? and category='work'"
               " limit 1", (ROOT_ID,))
out["steps"]["N3_identity_mismatch"] = {
    "correct_path_wrong_root": http(
        "GET", "/v1/simigo/is/file?root_id=" + (other_root[0]["root_id"] if other_root
                                                else "work-nope")
        + "&path=" + urllib.parse.quote(ALPHA)),
    "settled_digest_as_object_id": http(
        "GET", "/v1/simigo/is/object?id=" + settled_sha),
    "foreign_root_dependency": http(
        "GET", "/v1/simigo/is/dependency?id=" + urllib.parse.quote(
            f"file:work-00000000ffffffff/{ALPHA}", safe=":")),
    "path_traversal_rejected": http(
        "GET", "/v1/simigo/is/file?root_id=" + ROOT_ID
        + "&path=" + urllib.parse.quote("../../../../etc/hosts")),
    "es_cross_namespace_bind": chat("e4-cross-id-alpha", QUERY_ALPHA, max_tokens=24),
}
out["steps"]["N3_pool_namespace_rows"] = {
    "namespaces": sorted({p.name for p in pathlib.Path(
        f"{HOME}/.simigo/prefix-pool").glob("*") if p.is_dir()}),
    "entries": [str(p.relative_to(f"{HOME}/.simigo/prefix-pool"))
                for p in pathlib.Path(f"{HOME}/.simigo/prefix-pool").rglob("*.json")][:20],
}

out["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
path = EXP / f"e4-negatives-{time.strftime('%Y%m%d-%H%M%S')}.json"
path.write_text(json.dumps(out, ensure_ascii=False, indent=2, default=str))
print("WROTE", path)
for k, v in out["steps"].items():
    print("--", k, json.dumps(v, ensure_ascii=False, default=str)[:500])
