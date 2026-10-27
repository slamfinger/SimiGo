#!/usr/bin/env python3
"""Stage 3 / K1 real-model product-layer probe: settlement consumption with both
KV carriers simultaneously unreadable AND unwritable.

Reuses b7_probe.py's request shapes, trace bracketing and directory inventory
logic verbatim; only the environment is different:

  * runtime home  = <run>/home   (isolated DB, isolated trace)
  * KV carriers   = <run>/cache/prefix-pool , <run>/cache/branch-checkpoints
  * work root     = registered through the product API POST /v1/simigo/roots

Blocking technique: the whole <run>/cache directory is moved aside and the name
is replaced by a REGULAR FILE. Both KV paths then fail read (`contentsOfDirectory`
-> ENOTDIR) and fail write (`createDirectory` -> ENOTDIR) at the same time, and
any silent redirection would show up as new files elsewhere in the run tree or
in the real ~/.simigo, both of which are inventoried before and after.

Nothing here deletes user data: the moved cache is restored at the end, and the
marker file is only unlinked if its contents still match what this probe wrote.
"""
import hashlib, json, os, shutil, sqlite3, subprocess, sys, time
import urllib.error, urllib.request

REPO = "/Users/mr.simi/Documents/SimiGo"
HOME = os.path.expanduser("~")
REAL_SIMIGO = os.path.join(HOME, ".simigo")
R = os.environ["SIMIGO_STAGE3_RUN"]           # <run> root
SIMIGO = os.path.join(R, "run", "home")       # isolated SIMIGO_HOME
DB = os.path.join(SIMIGO, "simigo.sqlite3")
TRACE = os.path.join(SIMIGO, "logs/native_mlx_trace.log")
CACHE = os.path.join(R, "run", "cache")       # isolated SIMIGO_CACHE_ROOT
WORKROOT = os.path.join(R, "run", "workroot")
OUT = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(REPO, "build/b7/tools/declare-contract/declare-contract")
PORT = 8000
BASE = "http://127.0.0.1:%d" % PORT
EXPECT_ROOT_ID = os.environ.get("SIMIGO_K1_ROOT_ID", "work-000000004154195b")
BLOCK_MARKER = "simigo-k1-blocked-cache-root (regular file; both KV carriers ENOTDIR)\n"
STARTED = time.time()
NONCE = time.strftime("%Y%m%d-%H%M%S")

results = {
    "case": "K1",
    "nonce": NONCE,
    "started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "base_url": BASE,
    "run_root": R,
    "kv_cache_root": CACHE,
    "expected_root_id": EXPECT_ROOT_ID,
    "steps": {},
}


def log(msg):
    print("[K1 %s] %s" % (time.strftime("%H:%M:%S"), msg), flush=True)


def save():
    path = os.path.join(OUT, "results-K1-%s.json" % NONCE)
    with open(path, "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=1)
    results["results_path"] = path
    return path


# ---------------- HTTP ----------------

def post(path, payload, timeout=900):
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        BASE + path, data=data, headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            status = int(r.status)
    except urllib.error.HTTPError as e:
        raw = e.read()
        status = int(e.code)
    except Exception as e:
        return -1, {"error": repr(e)}, round(time.time() - t0, 3)
    try:
        body = json.loads(raw.decode())
    except Exception:
        body = {"raw": raw.decode(errors="replace")}
    return status, body, round(time.time() - t0, 3)


def get(path, timeout=60):
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
        time.sleep(5)
    raise SystemExit("SERVICE_NOT_READY last=%r" % (last,))


def output_text(body):
    parts = []
    for item in body.get("output") or []:
        for piece in item.get("content") or []:
            if isinstance(piece, dict) and piece.get("type") == "output_text":
                parts.append(piece.get("text") or "")
    return "\n".join(parts)


# ---------------- trace ----------------

def trace_offset():
    return os.path.getsize(TRACE) if os.path.exists(TRACE) else 0


def trace_since(offset):
    if not os.path.exists(TRACE):
        return ""
    with open(TRACE, "rb") as f:
        f.seek(offset)
        return f.read().decode(errors="replace")


GEN_KEYS = ("[MLX] prefill", "mode=", "ttft=", "poolBind", "cacheHitTokens")
KV_KEYS = ("poolBind", "poolRescan", "checkpoint", "safetensors", "snapshot",
           "continuation_branch", "continuation_admitted", "[LIFECYCLE]")


def generation_lines(text):
    return [ln.strip() for ln in text.splitlines()
            if any(k in ln for k in GEN_KEYS)]


def kv_lines(text):
    return [ln.strip() for ln in text.splitlines()
            if any(k in ln for k in KV_KEYS)]


def trace_digest(text):
    return [ln.strip() for ln in text.splitlines()
            if any(k in ln for k in
                   GEN_KEYS + KV_KEYS + ("[PROTOCOL] arrive", "NativeMLX ready"))]


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


def db_counters():
    out = {}
    for t in ("settlements", "execution_states", "settlement_bindings",
              "settlement_consumptions", "settlement_reuse_contracts",
              "checkpoints", "retrieval_settlements", "is_objects"):
        out[t] = db_one("SELECT count(*) AS n FROM %s;" % t)["n"]
    return out


def settlement_rows():
    return db_rows(
        "SELECT settlement_id, state_id, contract_version, validation_status, "
        "validity, settled_at FROM settlements ORDER BY settled_at;")


def tool(*args, retries=8):
    for attempt in range(retries):
        r = subprocess.run([TOOL, DB] + list(args),
                           capture_output=True, text=True)
        if r.returncode == 0:
            return json.loads(r.stdout)
        if "database is locked" in (r.stderr or "") and attempt + 1 < retries:
            time.sleep(2)
            continue
        raise SystemExit("TOOL_FAILED %r: %s" % (args, r.stderr.strip()))
    raise SystemExit("TOOL_BUSY %r" % (args,))


# ---------------- directory inventories ----------------

def dir_tree(root):
    if not os.path.isdir(root):
        return {"present": False, "file_count": 0, "total_bytes": 0,
                "listing_sha256": None, "files": [],
                "kind": kind_of(root)}
    files = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            p = os.path.join(dirpath, name)
            st = os.lstat(p)
            files.append({"rel": os.path.relpath(p, root), "size": st.st_size,
                          "mtime_ns": st.st_mtime_ns, "inode": st.st_ino})
    listing = "\n".join("%s|%d|%d|%d" % (f["rel"], f["size"], f["mtime_ns"],
                                          f["inode"]) for f in files)
    return {"present": True, "file_count": len(files),
            "total_bytes": sum(f["size"] for f in files),
            "listing_sha256": hashlib.sha256(listing.encode()).hexdigest(),
            "files": files, "kind": kind_of(root)}


def kind_of(path):
    if not os.path.lexists(path):
        return "absent"
    if os.path.isdir(path):
        return "directory"
    if os.path.islink(path):
        return "symlink"
    return "regular-file"


def kv_state():
    return {name: dir_tree(os.path.join(CACHE, name))
            for name in ("prefix-pool", "branch-checkpoints")}


def cache_root_state():
    return {"path": CACHE, "kind": kind_of(CACHE),
            "size": os.path.getsize(CACHE) if kind_of(CACHE) == "regular-file" else None,
            "sha256": (hashlib.sha256(open(CACHE, "rb").read()).hexdigest()
                       if kind_of(CACHE) == "regular-file" else None),
            "children": kv_state()}


def probe_rw(p):
    """Independent read/write probe of one KV carrier path."""
    read_err, write_err = None, None
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


def block_kv():
    dest = os.path.join(OUT, "isolation-cache")
    if os.path.isdir(dest):
        raise SystemExit("ISOLATION_DEST_EXISTS: %s (refusing to overwrite)" % dest)
    os.makedirs(dest)
    moved = None
    if os.path.isdir(CACHE):
        target = os.path.join(dest, "cache")
        shutil.move(CACHE, target)
        moved = target
    elif os.path.lexists(CACHE):
        raise SystemExit("CACHE_NOT_A_DIRECTORY_ALREADY: %s kind=%s"
                         % (CACHE, kind_of(CACHE)))
    with open(CACHE, "w") as f:
        f.write(BLOCK_MARKER)
    return {"moved_to": moved, "blocker": probe_rw(CACHE)}


def unblock_kv():
    st = kind_of(CACHE)
    if st != "regular-file":
        raise SystemExit("UNBLOCK_REFUSED: cache root kind=%s" % st)
    with open(CACHE, "rb") as f:
        data = f.read()
    if data.decode() != BLOCK_MARKER:
        raise SystemExit("UNBLOCK_REFUSED: blocker contents changed (%d bytes)"
                         % len(data))
    os.unlink(CACHE)
    dest = os.path.join(OUT, "isolation-cache", "cache")
    restored = None
    if os.path.isdir(dest):
        shutil.move(dest, CACHE)
        restored = True
    return {"restored_original": restored, "kind_after": kind_of(CACHE)}


def sweep_new_paths():
    """Look for any KV carrier anywhere inside the run tree and in the real home,
    i.e. prove no silent redirection."""
    found = []
    for base in (R, REAL_SIMIGO):
        for dirpath, dirnames, filenames in os.walk(base):
            if "isolation-cache" in dirpath:
                continue
            depth = os.path.relpath(dirpath, base).count(os.sep)
            if depth > 6:
                dirnames[:] = []
                continue
            for name in dirnames + filenames:
                if name in ("prefix-pool", "branch-checkpoints"):
                    p = os.path.join(dirpath, name)
                    found.append({"path": p, "kind": kind_of(p),
                                  "in": os.path.relpath(p, REAL_SIMIGO)
                                  if p.startswith(REAL_SIMIGO) else "run-tree"})
            dirnames.sort()
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


# ---------------- request bodies (same shapes as B-7) ----------------

CONTRACT = {"id": "simigo.settlement-consumption",
            "demand_class": "exact-repeat", "version": "v1", "extract": "content"}


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


def window(label, payload, path="/v1/responses", timeout=900):
    off = trace_offset()
    status, body, secs = post(path, payload, timeout=timeout)
    time.sleep(0.4)
    trace = trace_since(off)
    record = {"label": label, "path": path, "request": payload,
              "status": status, "seconds": secs, "body": body,
              "generation_lines": generation_lines(trace),
              "kv_lines": kv_lines(trace),
              "trace": trace_digest(trace),
              "trace_raw": trace}
    results["steps"][label] = record
    save()
    log("%s -> %s %.3fs generation_lines=%d kv_lines=%d"
        % (label, status, secs, len(record["generation_lines"]),
           len(record["kv_lines"])))
    return record


# ---------------- main ----------------

def main():
    if not os.path.exists(TOOL):
        raise SystemExit("tool missing: %s" % TOOL)

    model_id = wait_ready()
    exe = "/Applications/SimiGo.app/Contents/MacOS/SimiGo"
    pids = subprocess.run(["pgrep", "-f", exe],
                          capture_output=True, text=True).stdout.split()
    ps_eww = subprocess.run(["ps", "eww", "-p", (pids or ["0"])[0]],
                            capture_output=True, text=True).stdout.split()
    results["identity"] = {
        "model_id": model_id,
        "installed_exe_sha256": subprocess.run(
            ["shasum", "-a", "256", exe], capture_output=True, text=True
        ).stdout.split()[0],
        "app_pid": pids,
        "app_env": {kv.split("=", 1)[0]: kv.split("=", 1)[1]
                    for kv in ps_eww
                    if kv.startswith("SIMIGO_") and "=" in kv},
        "head": subprocess.run(["git", "-C", REPO, "rev-parse", "HEAD"],
                               capture_output=True, text=True).stdout.strip(),
        "trace_size": trace_offset(),
        "db_counters_start": db_counters(),
        "cache_root_start": cache_root_state(),
        "real_home_start": real_home_state(),
    }
    log("service ready model=%s pid=%s" % (model_id, results["identity"]["app_pid"]))
    save()

    # ---- 0. register work root through the product API ----
    os.makedirs(WORKROOT, exist_ok=True)
    for name, text in (("a.txt", "ALPHA-9f3c71\n"), ("b.txt", "BRAVO-4d8e20\n")):
        p = os.path.join(WORKROOT, name)
        if not os.path.exists(p):
            with open(p, "w") as f:
                f.write(text)
    rr_off = trace_offset()
    st, reg, _ = post("/v1/simigo/roots", {"path": WORKROOT}, timeout=120)
    results["steps"]["root-registration"] = {
        "status": st, "body": reg, "trace": trace_digest(trace_since(rr_off))}
    if st != 200 or reg.get("root_id") != EXPECT_ROOT_ID:
        raise SystemExit("ROOT_REGISTRATION_UNEXPECTED: %r" % reg)
    root_id = reg["root_id"]
    log("work root %s registered" % root_id)
    save()

    # ---- 1. real-model source settlement ----
    start_stamp = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(STARTED - 5))
    source_prompt = "只输出这一行，不要解释：K1-SETTLED-%s" % NONCE
    source = window(
        "source-chat-generation",
        {"model": model_id, "session_id": "k1-source-%s" % NONCE,
         "max_tokens": 96,
         "messages": [{"role": "system",
                       "content": "你是精确的标记输出器，只输出用户要求的那一行。"},
                      {"role": "user", "content": source_prompt}]},
        path="/v1/chat/completions")
    if source["status"] != 200:
        raise SystemExit("SOURCE_GENERATION_FAILED: %r" % source["body"])
    choices = source["body"].get("choices") or []
    source_text = ((choices[0].get("message") or {}).get("content") or "") \
        if choices else ""
    time.sleep(2.0)
    row = db_one(
        "SELECT settlement_id, state_id, settled_at FROM settlements "
        "WHERE state_id IN (SELECT state_id FROM execution_states "
        "  WHERE state_id LIKE 'chat-%' AND substr(created_at,1,19) >= ?) "
        "ORDER BY settled_at DESC LIMIT 1;", (start_stamp,))
    if not row:
        raise SystemExit("NO_SOURCE_SETTLEMENT after chat generation")
    source_id, source_state = row["settlement_id"], row["state_id"]
    inspected = tool("status", source_id)
    value = inspected["content"]
    results["source"] = {
        "settlement_id": source_id, "state_id": source_state,
        "settled_at": row["settled_at"], "generated_text": source_text,
        "settled_value": value,
        "payload_digest_ok": inspected["payload_digest_ok"],
        "payload_digest": inspected["payload_digest"],
        "bindings": inspected["bindings"],
        "usage": source["body"].get("usage"),
        "generation_line_count": len(source["generation_lines"]),
        "kv_line_count": len(source["kv_lines"]),
        "marker_matched": value.strip() == ("K1-SETTLED-%s" % NONCE),
    }
    if not value.strip() or not inspected["payload_digest_ok"]:
        raise SystemExit("SOURCE_SETTLEMENT_UNUSABLE: %r" % results["source"])
    log("source settlement %s value=%r" % (source_id, value))
    save()

    # ---- 2. declare the reuse contract (native API) ----
    query = "k1 exact repeat %s" % NONCE
    demand = tool("demand", query, root_id)
    declaration = tool("declare", source_id, query, root_id)
    stored = tool("contract", source_id)
    if declaration["canonical_digest"] != demand["digest"]:
        raise SystemExit("DECLARATION_DIGEST_MISMATCH %r vs %r"
                         % (declaration, demand))
    results["contract"] = {"query": query, "root_id": root_id,
                           "canonical_entries": demand["entries"],
                           "canonical": demand["canonical"],
                           "canonical_digest": demand["digest"],
                           "declaration": declaration, "stored": stored}
    log("contract declared digest=%s" % demand["digest"][:16])
    save()

    # ---- 3. block BOTH KV carriers (unreadable + unwritable) ----
    counters_before = db_counters()
    settlements_before = settlement_rows()
    cache_before = cache_root_state()
    blocked = block_kv()
    rw_during = {name: probe_rw(os.path.join(CACHE, name))
                 for name in ("prefix-pool", "branch-checkpoints")}
    results["block"] = {"cache_before": cache_before, "action": blocked,
                        "cache_after": cache_root_state(),
                        "probe_read_write": rw_during,
                        "db_counters_before": counters_before,
                        "settlement_ids_before": [r["settlement_id"]
                                                  for r in settlements_before]}
    save()
    for name, probe in rw_during.items():
        log("blocked %s listdir=%s makedirs=%s"
            % (name, probe["listdir_error"], probe["makedirs_error"]))
    if any(p["makedirs_error"] == "WRITE_SUCCEEDED" for p in rw_during.values()):
        raise SystemExit("BLOCK_FAILED: a KV carrier path is still writable")

    # ---- 4. consumption windows ----
    first = window("consume-positive",
                   consumption_body(model_id, source_id, query, [root_id]))
    second = window("consume-second-request",
                    consumption_body(model_id, source_id, query, [root_id]))
    bogus = window("consume-refusal-control",
                   consumption_body(model_id, "set-does-not-exist-%s" % NONCE,
                                    query, [root_id]))
    rw_after = {name: probe_rw(os.path.join(CACHE, name))
                for name in ("prefix-pool", "branch-checkpoints")}
    cache_after_consumption = cache_root_state()
    counters_after = db_counters()
    settlements_after = settlement_rows()
    new_settlements = [r for r in settlements_after
                       if r["settlement_id"] not in
                       {b["settlement_id"] for b in settlements_before}]
    consumption_rows = db_rows(
        "SELECT consumption_id, source_settlement_id, consumer_settlement_id, "
        "contract_id, model_calls, created_at FROM settlement_consumptions "
        "ORDER BY created_at;")
    results["during_block"] = {
        "cache_root": cache_after_consumption,
        "probe_read_write_after": rw_after,
        "db_counters_after": counters_after,
        "db_counter_delta": {k: counters_after[k] - counters_before[k]
                             for k in counters_after},
        "new_settlement_rows": new_settlements,
        "settlement_consumption_rows": consumption_rows,
        "sweep_for_redirected_kv": sweep_new_paths(),
        "real_home_after": real_home_state(),
    }
    save()
    log("consumption done: new settlement rows=%d" % len(new_settlements))

    # ---- 5. unblock + sensitivity control ----
    restore = unblock_kv()
    control = window("control-generation-after-unblock",
                     {"model": model_id, "session_id": "k1-control-%s" % NONCE,
                      "max_tokens": 48,
                      "messages": [{"role": "system",
                                    "content": "你是精确的标记输出器，只输出用户要求的那一行。"},
                                   {"role": "user",
                                    "content": "只输出这一行，不要解释：K1-CONTROL-%s" % NONCE}]},
                     path="/v1/chat/completions")
    # give the idle-suspend / checkpoint writer a chance to run
    suspend_wait = []
    for _ in range(12):
        time.sleep(5)
        st = cache_root_state()
        suspend_wait.append({"t": time.strftime("%H:%M:%S"),
                             "prefix_pool_files": st["children"]["prefix-pool"]["file_count"],
                             "branch_checkpoint_files": st["children"]["branch-checkpoints"]["file_count"]})
        if st["children"]["branch-checkpoints"]["file_count"] or \
           st["children"]["prefix-pool"]["file_count"]:
            break
    results["unblock"] = {"restore": restore,
                          "cache_after_unblock": cache_root_state(),
                          "control_generation_lines": len(control["generation_lines"]),
                          "kv_activity_samples": suspend_wait,
                          "control_kv_lines": control["kv_lines"]}
    save()

    # ---- 6. assertions ----
    positive_body = first["body"]
    positive = positive_body.get("settlement_consumption") or {}
    second_pos = second["body"].get("settlement_consumption") or {}
    gen_new_settlements = [r for r in new_settlements
                           if (r["state_id"] or "").startswith("chat-")
                           and r["settlement_id"] != source_id]
    checks = {
        "block_effective_read": all(p["listdir_error"] for p in rw_after.values()),
        "block_effective_write": all(p["makedirs_error"] != "WRITE_SUCCEEDED"
                                     for p in rw_after.values()),
        "no_kv_files_created_during_block":
            not cache_after_consumption["children"]["prefix-pool"]["present"]
            and not cache_after_consumption["children"]["branch-checkpoints"]["present"],
        "no_kv_redirection": not [f for f in results["during_block"]["sweep_for_redirected_kv"]
                                  if f["path"].startswith(R)],
        "real_home_untouched": results["identity"]["real_home_start"]
            == results["during_block"]["real_home_after"],
        "positive_status_200": first["status"] == 200,
        "model_calls_zero": positive.get("model_calls") == 0,
        "derived_settlement_true": positive.get("derived_settlement") is True,
        "usage_zero": all((positive_body.get("usage") or {}).get(k) in (0, None)
                          for k in ("prompt_tokens", "completion_tokens",
                                    "total_tokens")),
        "text_is_settled_value": output_text(positive_body).strip() == value.strip(),
        "no_generation_lines_positive": len(first["generation_lines"]) == 0,
        "no_generation_lines_second": len(second["generation_lines"]) == 0,
        "second_request_model_calls_zero": second_pos.get("model_calls") == 0,
        "no_new_generation_settlement": not gen_new_settlements,
        "probe_saw_generation_lines_in_source_window":
            len(source["generation_lines"]) > 0,
        "refusal_control_not_200_ok": bogus["status"] != 200
            or (bogus["body"].get("settlement_consumption") or {}).get("model_calls", 0) == 0,
        "refusal_control_no_generation": len(bogus["generation_lines"]) == 0,
    }
    results["checks"] = checks
    results["summary"] = {
        "passed": sum(1 for v in checks.values() if v),
        "total": len(checks),
        "failures": [k for k, v in checks.items() if not v],
        "new_generation_settlements": gen_new_settlements,
        "model_calls_total_persisted":
            sum(r["model_calls"] for r in consumption_rows),
    }
    save()
    log("K1 checks %d/%d failures=%s"
        % (results["summary"]["passed"], results["summary"]["total"],
           results["summary"]["failures"]))


if __name__ == "__main__":
    main()
