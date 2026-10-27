#!/usr/bin/env python3
"""Shared helpers for the Stage 3 product-layer K-series probes.

Same request shapes, trace bracketing and inventory logic as
research/agent-runs/.../b7-20261027-0338/b7_probe.py; only the environment is
different (isolated run root; KV carriers under <run>/run/cache).

Blocking is cross-process safe: <run>/run/cache is moved to
<run>/isolation-cache/cache and replaced by a regular marker file, so the two KV
carrier paths stay unreadable AND unwritable for every later phase, including
after the app process is terminated and restarted. The block is recorded in
<run>/block-state.json so a later phase can restore it (never by deletion).
"""
import hashlib, json, os, shutil, sqlite3, subprocess, time
import urllib.error, urllib.request

REPO = "/Users/mr.simi/Documents/SimiGo"
HOME = os.path.expanduser("~")
REAL_SIMIGO = os.path.join(HOME, ".simigo")
R = os.environ["SIMIGO_STAGE3_RUN"]
SIMIGO = os.path.join(R, "run", "home")
DB = os.path.join(SIMIGO, "simigo.sqlite3")
TRACE = os.path.join(SIMIGO, "logs/native_mlx_trace.log")
CACHE = os.path.join(R, "run", "cache")
WORKROOT = os.path.join(R, "run", "workroot")
BLOCK_STATE = os.path.join(R, "block-state.json")
TOOL = os.path.join(REPO, "build/b7/tools/declare-contract/declare-contract")
BASE = "http://127.0.0.1:8000"
ROOT_ID = os.environ.get("SIMIGO_K1_ROOT_ID", "work-000000004154195b")
BLOCK_MARKER = "simigo-k1-blocked-cache-root (regular file; both KV carriers ENOTDIR)\n"

GEN_KEYS = ("[MLX] prefill", "mode=", "ttft=", "poolBind", "cacheHitTokens")
KV_KEYS = ("poolBind", "poolRescan", "poolExport", "cacheSave", "cacheLoad",
           "checkpoint", "safetensors", "snapshot", "continuation_branch",
           "continuation_admitted", "[LIFECYCLE]", "[MEM]")


def log(tag, msg):
    print("[%s %s] %s" % (tag, time.strftime("%H:%M:%S"), msg), flush=True)


def sha_json(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


# ---------------- HTTP ----------------

def post(path, payload, timeout=900):
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        BASE + path, data=data, headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw, status = r.read(), int(r.status)
    except urllib.error.HTTPError as e:
        raw, status = e.read(), int(e.code)
    except Exception as e:
        return -1, {"error": repr(e)}, round(time.time() - t0, 3)
    try:
        body = json.loads(raw.decode())
    except Exception:
        body = {"raw": raw.decode(errors="replace")}
    return status, body, round(time.time() - t0, 3)


def get(path, timeout=120):
    try:
        with urllib.request.urlopen(BASE + path, timeout=timeout) as r:
            return int(r.status), json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return int(e.code), json.loads(e.read().decode())
        except Exception:
            return int(e.code), {}
    except Exception as e:
        return -1, {"error": repr(e)}


def wait_ready(limit=900):
    deadline = time.time() + limit
    last = None
    while time.time() < deadline:
        status, body = get("/v1/models", timeout=10)
        if status == 200 and body.get("data"):
            return body["data"][0].get("id")
        last = (status, body)
        time.sleep(4)
    raise SystemExit("SERVICE_NOT_READY last=%r" % (last,))


def output_text(body):
    t = body.get("text")
    if isinstance(t, str):
        return t
    parts = []
    for item in body.get("output") or []:
        for piece in item.get("content") or []:
            if isinstance(piece, dict) and piece.get("type") == "output_text":
                parts.append(piece.get("text") or "")
    if parts:
        return "\n".join(parts)
    choices = body.get("choices") or []
    if choices:
        return (choices[0].get("message") or {}).get("content") or ""
    return ""


# ---------------- trace ----------------

def trace_offset():
    return os.path.getsize(TRACE) if os.path.exists(TRACE) else 0


def trace_since(offset):
    if not os.path.exists(TRACE):
        return ""
    with open(TRACE, "rb") as f:
        f.seek(offset)
        return f.read().decode(errors="replace")


def lines_with(text, keys):
    return [ln.strip() for ln in text.splitlines() if any(k in ln for k in keys)]


def generation_lines(text):
    return lines_with(text, GEN_KEYS)


def kv_lines(text):
    return lines_with(text, KV_KEYS)


# ---------------- DB (read-only) ----------------

def db_rows(sql, args=()):
    con = sqlite3.connect("file:%s?mode=ro" % DB, uri=True)
    con.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in con.execute(sql, args).fetchall()]
    finally:
        con.close()


def db_one(sql, args=()):
    rows = db_rows(sql, args)
    return rows[0] if rows else None


COUNTER_TABLES = ("settlements", "execution_states", "settlement_bindings",
                  "settlement_consumptions", "settlement_reuse_contracts",
                  "checkpoints", "retrieval_settlements", "is_objects",
                  "chat_messages", "chat_execution_links", "information_demands",
                  "information_advancements")


def db_counters():
    return {t: db_one("SELECT count(*) AS n FROM %s;" % t)["n"]
            for t in COUNTER_TABLES}


def settlement_rows():
    return db_rows("SELECT settlement_id, state_id, contract_version, "
                   "validation_status, validity, settled_at FROM settlements "
                   "ORDER BY settled_at;")


def tool(*args, retries=8):
    for attempt in range(retries):
        r = subprocess.run([TOOL, DB] + list(args), capture_output=True, text=True)
        if r.returncode == 0:
            return json.loads(r.stdout)
        if "database is locked" in (r.stderr or "") and attempt + 1 < retries:
            time.sleep(2)
            continue
        raise SystemExit("TOOL_FAILED %r: %s" % (args, r.stderr.strip()))
    raise SystemExit("TOOL_BUSY %r" % (args,))


# ---------------- inventories ----------------

def kind_of(path):
    if not os.path.lexists(path):
        return "absent"
    if os.path.isdir(path):
        return "directory"
    if os.path.islink(path):
        return "symlink"
    return "regular-file"


def dir_tree(root):
    if not os.path.isdir(root):
        return {"present": False, "file_count": 0, "total_bytes": 0,
                "listing_sha256": None, "files": [], "kind": kind_of(root)}
    files = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            p = os.path.join(dirpath, name)
            st = os.lstat(p)
            files.append({"rel": os.path.relpath(p, root), "size": st.st_size,
                          "mtime_ns": st.st_mtime_ns, "inode": st.st_ino})
        dirnames.sort()
    listing = "\n".join("%s|%d|%d|%d" % (f["rel"], f["size"], f["mtime_ns"],
                                          f["inode"]) for f in files)
    return {"present": True, "file_count": len(files),
            "total_bytes": sum(f["size"] for f in files),
            "listing_sha256": hashlib.sha256(listing.encode()).hexdigest(),
            "files": files, "kind": kind_of(root)}


def kv_state():
    return {n: dir_tree(os.path.join(CACHE, n))
            for n in ("prefix-pool", "branch-checkpoints")}


def cache_root_state():
    kind = kind_of(CACHE)
    return {"path": CACHE, "kind": kind,
            "size": os.path.getsize(CACHE) if kind == "regular-file" else None,
            "sha256": (hashlib.sha256(open(CACHE, "rb").read()).hexdigest()
                       if kind == "regular-file" else None),
            "children": kv_state()}


def probe_rw(p):
    read_err = write_err = None
    try:
        os.listdir(p)
    except Exception as e:
        read_err = repr(e)
    try:
        os.makedirs(p, exist_ok=True)
        write_err = "WRITE_SUCCEEDED"
    except Exception as e:
        write_err = repr(e)
    return {"path": p, "listdir_error": read_err, "makedirs_error": write_err}


def block_enforced():
    out = {n: probe_rw(os.path.join(CACHE, n))
           for n in ("prefix-pool", "branch-checkpoints")}
    ok = all(p["listdir_error"] and p["makedirs_error"] != "WRITE_SUCCEEDED"
             for p in out.values())
    return ok, out


def block_kv(tag):
    if os.path.exists(BLOCK_STATE):
        raise SystemExit("ALREADY_BLOCKED (see %s)" % BLOCK_STATE)
    dest = os.path.join(R, "isolation-cache", tag + "-" + time.strftime("%H%M%S"))
    os.makedirs(dest)
    moved = None
    if os.path.isdir(CACHE):
        moved = os.path.join(dest, "cache")
        shutil.move(CACHE, moved)
    elif os.path.lexists(CACHE):
        raise SystemExit("CACHE_NOT_A_DIRECTORY: kind=%s" % kind_of(CACHE))
    with open(CACHE, "w") as f:
        f.write(BLOCK_MARKER)
    ok, probes = block_enforced()
    state = {"blocked_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
             "blocked_at_ns": time.time_ns(), "moved_to": moved,
             "marker_sha256": hashlib.sha256(BLOCK_MARKER.encode()).hexdigest(),
             "enforced": ok, "probe": probes}
    with open(BLOCK_STATE, "w") as f:
        json.dump(state, f, indent=1)
    log(tag, "KV blocked enforced=%s" % ok)
    if not ok:
        raise SystemExit("BLOCK_NOT_ENFORCED: %r" % probes)
    return state


def unblock_kv(tag):
    if not os.path.exists(BLOCK_STATE):
        raise SystemExit("NOT_BLOCKED (no %s)" % BLOCK_STATE)
    with open(BLOCK_STATE) as f:
        state = json.load(f)
    st = kind_of(CACHE)
    if st != "regular-file":
        raise SystemExit("UNBLOCK_REFUSED: cache kind=%s" % st)
    with open(CACHE, "rb") as f:
        if hashlib.sha256(f.read()).hexdigest() != state["marker_sha256"]:
            raise SystemExit("UNBLOCK_REFUSED: marker digest changed")
    os.unlink(CACHE)
    restored = None
    if state.get("moved_to") and os.path.isdir(state["moved_to"]):
        shutil.move(state["moved_to"], CACHE)
        restored = True
    state["restored_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    state["restored_original"] = restored
    state["cache_after"] = cache_root_state()
    with open(BLOCK_STATE + ".restored.json", "w") as f:
        json.dump(state, f, indent=1)
    os.unlink(BLOCK_STATE)
    log(tag, "KV unblocked restored=%s kind=%s" % (restored, kind_of(CACHE)))
    return state


def sweep_kv_paths():
    """Any prefix-pool / branch-checkpoints node in the run tree or real home:
    proves no silent redirection while the intended root is a regular file."""
    found = []
    for base in (R, REAL_SIMIGO):
        for dirpath, dirnames, filenames in os.walk(base):
            if "isolation-cache" in dirpath:
                continue
            if os.path.relpath(dirpath, base).count(os.sep) > 6:
                dirnames[:] = []
                continue
            dirnames.sort()
            for name in list(dirnames) + sorted(filenames):
                if name in ("prefix-pool", "branch-checkpoints"):
                    p = os.path.join(dirpath, name)
                    found.append({"path": p, "kind": kind_of(p),
                                 "where": "run-tree"
                                 if not p.startswith(REAL_SIMIGO) else "real-home"})
    return found


def real_home_state():
    out = {}
    for name in ("prefix-pool", "branch-checkpoints", "simigo.sqlite3"):
        p = os.path.join(REAL_SIMIGO, name)
        st = {"kind": kind_of(p)}
        if os.path.lexists(p):
            s = os.lstat(p)
            st["mtime_ns"] = s.st_mtime_ns
            st["mtime"] = time.strftime("%Y-%m-%d %H:%M:%S",
                                        time.localtime(s.st_mtime))
        if os.path.isdir(p):
            st["entries"] = len(os.listdir(p))
        out[name] = st
    return out


def app_state():
    exe = "/Applications/SimiGo.app/Contents/MacOS/SimiGo"
    pids = subprocess.run(["pgrep", "-f", exe],
                          capture_output=True, text=True).stdout.split()
    env = {}
    if pids:
        out = subprocess.run(["ps", "eww", "-p", pids[0]],
                             capture_output=True, text=True).stdout.split()
        env = {kv.split("=", 1)[0]: kv.split("=", 1)[1]
               for kv in out if kv.startswith("SIMIGO_") and "=" in kv}
    return {"pids": pids, "env": env,
            "exe_sha256": subprocess.run(["shasum", "-a", "256", exe],
                                         capture_output=True,
                                         text=True).stdout.split()[0],
            "model_id": (get("/v1/models", timeout=10)[1].get("data") or [{}])[0].get("id")}


# ---------------- settlement consumption bodies (B-7 shapes) ----------------

CONTRACT = {"id": "simigo.settlement-consumption", "demand_class": "exact-repeat",
            "version": "v1", "extract": "content"}


def consumption_body(model_id, source, query, roots, allow_recompute=False,
                     identity=None, include=True, contract=None):
    body = {"model": model_id, "input": "consume", "max_output_tokens": 64}
    if include:
        entry = {"source_settlement_id": source,
                 "contract": dict(contract or CONTRACT),
                 "query": query, "root_ids": list(roots)}
        if allow_recompute:
            entry["allow_recompute"] = True
        if identity:
            entry["identity"] = identity
        body["settlement_consumption"] = entry
    return body


def window(results, tag, label, payload, path="/v1/responses", timeout=900):
    off = trace_offset()
    status, body, secs = post(path, payload, timeout=timeout)
    time.sleep(0.4)
    trace = trace_since(off)
    record = {"label": label, "path": path, "request": payload, "status": status,
              "seconds": secs, "body": body,
              "generation_lines": generation_lines(trace),
              "kv_lines": kv_lines(trace), "trace_raw": trace,
              "at": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
    results["steps"][label] = record
    save(results)
    log(tag, "%s -> %s %.3fs gen=%d kv=%d" % (label, status, secs,
                                              len(record["generation_lines"]),
                                              len(record["kv_lines"])))
    return record


def new_results(case, nonce):
    return {"case": case, "nonce": nonce,
            "started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "run_root": R, "kv_cache_root": CACHE, "root_id": ROOT_ID,
            "steps": {}}


def _default(o):
    if isinstance(o, (bytes, bytearray)):
        return o.decode(errors="replace")
    return str(o)


def save(results):
    path = os.path.join(R, "results-%s-%s.json" % (results["case"], results["nonce"]))
    with open(path, "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=1, default=_default)
    return path


def write_state(name, obj):
    with open(os.path.join(R, name), "w") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1, default=_default)
    return name


def read_state(name):
    with open(os.path.join(R, name)) as f:
        return json.load(f)


def settle_source(results, tag, model_id, nonce, prefix):
    """One real model generation that must produce a settled row."""
    started = time.time()
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(started - 5))
    marker = "%s-SETTLED-%s" % (prefix, nonce)
    rec = window(results, tag, "source-chat-generation-%s" % prefix,
                 {"model": model_id, "session_id": "%s-source-%s" % (prefix, nonce),
                  "max_tokens": 96,
                  "messages": [{"role": "system",
                                "content": "你是精确的标记输出器，只输出用户要求的那一行。"},
                               {"role": "user",
                                "content": "只输出这一行，不要解释：%s" % marker}]},
                 path="/v1/chat/completions")
    if rec["status"] != 200:
        raise SystemExit("SOURCE_GENERATION_FAILED: %r" % rec["body"])
    time.sleep(2.0)
    row = db_one("SELECT settlement_id, state_id, settled_at FROM settlements "
                 "WHERE state_id IN (SELECT state_id FROM execution_states "
                 "WHERE state_id LIKE 'chat-%' AND substr(created_at,1,19) >= ?) "
                 "ORDER BY settled_at DESC LIMIT 1;", (stamp,))
    if not row:
        raise SystemExit("NO_SOURCE_SETTLEMENT after chat generation")
    inspected = tool("status", row["settlement_id"])
    out = dict(row)
    out.update({"session_id": "%s-source-%s" % (prefix, nonce),
                "marker": marker,
                "generated_text": output_text(rec["body"]),
                "settled_value": inspected["content"],
                "payload_digest_ok": inspected["payload_digest_ok"],
                "payload_digest": inspected["payload_digest"],
                "generation_line_count": len(rec["generation_lines"]),
                "marker_matched": inspected["content"].strip() == marker})
    if not out["payload_digest_ok"] or not out["marker_matched"]:
        raise SystemExit("SOURCE_SETTLEMENT_UNUSABLE: %r" % out)
    log(tag, "source settlement %s value=%r" % (out["settlement_id"],
                                                out["settled_value"]))
    return out


def declare_contract(tag, source_id, query):
    demand = tool("demand", query, ROOT_ID)
    declaration = tool("declare", source_id, query, ROOT_ID)
    stored = tool("contract", source_id)
    if declaration["canonical_digest"] != demand["digest"]:
        raise SystemExit("DECLARATION_DIGEST_MISMATCH %r vs %r" % (declaration, demand))
    log(tag, "contract declared digest=%s" % demand["digest"][:16])
    return {"query": query, "root_id": ROOT_ID, "canonical": demand["canonical"],
            "canonical_digest": demand["digest"], "declaration": declaration,
            "stored": stored}
