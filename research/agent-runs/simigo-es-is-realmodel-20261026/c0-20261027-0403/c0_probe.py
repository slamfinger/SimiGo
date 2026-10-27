#!/usr/bin/env python3
"""C-0 phase 1: real file-content-change invalidation chain, PRE-FIX.

Runs against the INSTALLED pre-fix Release build (expects exe sha 83635c73...)
and a real model. It never touches the user's own work root, the product DB
beyond ordinary product APIs, or the two KV directories.

Sequence (owner-ordered):
  1. build one throwaway work root of OUR OWN files and register it through the
     production entry `PUT /v1/simigo/roots`;
  2. one real chat generation whose query only our file matches, so the
     production IS demand binds our file to the retrieval settlement and the
     ES settlement gets its information-demand edge;
  3. declare the reuse contract (native tool, no hand-written SQL) and prove
     explicit consumption succeeds with zero model calls;
  4. change OUR file's content, re-scan through the SAME production entry,
     read the invalidation state from the DB;
  5. attempt consumption again (plain and allow_recompute) and record the
     HTTP terminal, model-trace window and ledger deltas.

Every hard check fails loudly; the expected PRE-FIX defect (admission refusal
classified as 500 instead of the contract's 422) is RECORDED, not asserted
away.
"""
import hashlib, json, os, sqlite3, subprocess, sys, time
import urllib.error, urllib.request

REPO = "/Users/mr.simi/Documents/SimiGo"
HOME = os.path.expanduser("~")
SIMIGO = os.path.join(HOME, ".simigo")
DB = os.path.join(SIMIGO, "simigo.sqlite3")
TRACE = os.path.join(SIMIGO, "logs/native_mlx_trace.log")
OUT = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.join(OUT, "root")
TOOL = os.path.join(REPO, "build/b7/tools/declare-contract/declare-contract")
EXE = "/Applications/SimiGo.app/Contents/MacOS/SimiGo"
EXPECTED_PRE_FIX_EXE = (
    "83635c736d7f913ebc63ffacbed29edbeb98ccc02e699d1ab11a870f02e32b89")
PORT = 8000
BASE = "http://127.0.0.1:%d" % PORT
NONCE = time.strftime("%Y%m%d-%H%M%S")
MARKER = "C0DEPMARK" + NONCE.replace("-", "")
SETTLED = "C0-SETTLED-" + NONCE
QUERY = "c0 exact repeat " + NONCE
PRIMARY = "marker_primary.md"
SECONDARY = "marker_secondary.md"

results = {
    "nonce": NONCE,
    "phase": "pre-fix",
    "started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "base_url": BASE,
    "isolated_root_dir": ROOT_DIR,
    "steps": {},
}


def log(msg):
    print("[C0 %s] %s" % (time.strftime("%H:%M:%S"), msg), flush=True)


def save():
    path = os.path.join(OUT, "results-pre-%s.json" % NONCE)
    with open(path, "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=1)
    return path


def fail(code, detail=None):
    results["failure"] = {"code": code, "detail": detail}
    path = save()
    log("FAIL %s %r (evidence %s)" % (code, detail, path))
    raise SystemExit(1)


# ---------------- HTTP ----------------

def request(method, path, payload=None, timeout=900):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        BASE + path, data=data, method=method,
        headers={"Content-Type": "application/json"})
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
    fail("SERVICE_NOT_READY", last)


def error_fields(body):
    err = (body or {}).get("error") or {}
    return {
        "error_kind": err.get("error_kind"),
        "reason_code": err.get("reason_code"),
        "type": err.get("type"),
        "message": err.get("message"),
    }


# ---------------- trace ----------------

GEN_KEYS = ("[MLX] prefill", "mode=", "ttft=", "poolBind", "cacheHitTokens",
            "poolExport", "cacheSave")


def trace_offset():
    return os.path.getsize(TRACE) if os.path.exists(TRACE) else 0


def trace_since(off):
    if not os.path.exists(TRACE):
        return ""
    with open(TRACE, "rb") as f:
        f.seek(off)
        return f.read().decode(errors="replace")


def generation_lines(text):
    return [ln.strip() for ln in text.splitlines()
            if any(k in ln for k in GEN_KEYS)]


def window(label, payload, path="/v1/responses", timeout=900):
    off = trace_offset()
    t_start = time.time()
    status, body, secs = request("POST", path, payload, timeout=timeout)
    time.sleep(0.5)
    trace = trace_since(off)
    record = {
        "label": label,
        "path": path,
        "request": payload,
        "t_start": t_start,
        "t_end": time.time(),
        "status": status,
        "seconds": secs,
        "body": body,
        "error": error_fields(body) if status >= 400 else None,
        "generation_lines": generation_lines(trace),
    }
    results["steps"][label] = record
    save()
    log("%s -> %s %.3fs generation_lines=%d"
        % (label, status, secs, len(record["generation_lines"])))
    return record


# ---------------- DB (read-only) ----------------

def db_rows(sql, args=(), retries=8):
    for attempt in range(retries):
        con = sqlite3.connect("file:%s?mode=ro" % DB, uri=True, timeout=10)
        con.row_factory = sqlite3.Row
        try:
            return [dict(r) for r in con.execute(sql, args).fetchall()]
        except sqlite3.OperationalError as e:
            if "locked" in str(e) and attempt + 1 < retries:
                time.sleep(1)
                continue
            raise
        finally:
            con.close()
    raise SystemExit("DB_BUSY")


def db_one(sql, args=()):
    rows = db_rows(sql, args)
    return rows[0] if rows else None


def tool(*args, retries=6):
    for attempt in range(retries):
        r = subprocess.run([TOOL, DB] + list(args),
                           capture_output=True, text=True)
        if r.returncode == 0:
            return json.loads(r.stdout)
        if "database is locked" in (r.stderr or "") and attempt + 1 < retries:
            time.sleep(2)
            continue
        fail("TOOL_FAILED", {"args": args, "stderr": r.stderr.strip()})
    fail("TOOL_BUSY", args)


def counts():
    return db_one("""
    SELECT
      (SELECT COUNT(*) FROM settlements) AS settlements,
      (SELECT COUNT(*) FROM execution_states) AS states,
      (SELECT COUNT(*) FROM settlement_consumptions) AS consumptions,
      (SELECT COUNT(*) FROM settlement_reuse_contracts) AS contracts,
      (SELECT COUNT(*) FROM information_demands) AS demands,
      (SELECT COUNT(*) FROM dependency_edges) AS edges,
      (SELECT COUNT(*) FROM settlement_bindings) AS bindings;
    """)


def backup_db(label):
    dest = os.path.join(OUT, "db-%s-%s.sqlite3" % (label, NONCE))
    if os.path.exists(dest):
        fail("BACKUP_PATH_COLLISION", dest)
    r = subprocess.run(["sqlite3", DB, ".backup '%s'" % dest],
                       capture_output=True, text=True)
    if r.returncode != 0:
        fail("BACKUP_FAILED", r.stderr.strip())
    h = hashlib.sha256()
    with open(dest, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    info = {"path": dest, "sha256": h.hexdigest(),
            "size": os.path.getsize(dest)}
    log("db backup %s" % label)
    return info


# ---------------- directories ----------------

def dir_tree(root):
    if not os.path.isdir(root):
        return {"present": False, "file_count": 0,
                "listing_sha256": None}
    rows = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            p = os.path.join(dirpath, name)
            st = os.lstat(p)
            rows.append("%s|%d|%d|%d" % (
                os.path.relpath(p, root), st.st_size,
                st.st_mtime_ns, st.st_ino))
    return {
        "present": True,
        "file_count": len(rows),
        "listing_sha256": hashlib.sha256("\n".join(rows).encode()).hexdigest(),
        "files": rows,
    }


def two_dirs():
    return {
        "prefix_pool": dir_tree(os.path.join(SIMIGO, "prefix-pool")),
        "branch_checkpoints": dir_tree(os.path.join(SIMIGO, "branch-checkpoints")),
    }


def listing_rows(tree):
    out = {}
    for row in tree.get("files") or []:
        rel, size, mtime_ns, inode = row.split("|")
        out[rel] = {"size": int(size), "mtime_ns": int(mtime_ns),
                    "inode": int(inode)}
    return out


# ---------------- request bodies ----------------

CONTRACT = {
    "id": "simigo.settlement-consumption",
    "demand_class": "exact-repeat",
    "version": "v1",
    "extract": "content",
}


def consumption_body(model_id, source, allow_recompute=False):
    entry = {
        "source_settlement_id": source,
        "contract": dict(CONTRACT),
        "query": QUERY,
        "root_ids": [results["root"]["root_id"]],
    }
    if allow_recompute:
        entry["allow_recompute"] = True
    return {"model": model_id, "input": "consume", "max_output_tokens": 64,
            "settlement_consumption": entry}


# ---------------- main ----------------

def main():
    if not os.path.exists(TOOL):
        fail("TOOL_MISSING", TOOL)
    model_id = wait_ready()
    exe_sha = subprocess.run(
        ["shasum", "-a", "256", EXE], capture_output=True,
        text=True).stdout.split()[0]
    results["identity"] = {
        "model_id": model_id,
        "installed_exe_sha256": exe_sha,
        "pre_fix_build": exe_sha == EXPECTED_PRE_FIX_EXE,
        "app_pid": subprocess.run(["pgrep", "-f", EXE],
                                  capture_output=True, text=True).stdout.split(),
        "head": subprocess.run(["git", "-C", REPO, "rev-parse", "HEAD"],
                               capture_output=True, text=True).stdout.strip(),
        "diff_sha256": subprocess.run(
            ["bash", "-lc", "git -C %s diff | shasum -a 256" % REPO],
            capture_output=True, text=True).stdout.strip(),
        "trace_size": trace_offset(),
    }
    if not results["identity"]["pre_fix_build"]:
        fail("NOT_THE_PRE_FIX_BUILD", exe_sha)
    log("service ready model=%s exe=%s" % (model_id, exe_sha[:16]))
    save()

    # ---- 0. baseline: KV dirs, DB counters, unique backup ----
    results["baseline"] = {
        "counts": counts(),
        "directories": two_dirs(),
        "db_backup": backup_db("pre"),
    }
    save()

    # ---- 1. our own root, registered through the production entry ----
    os.makedirs(ROOT_DIR, exist_ok=True)
    user_line = "%s 只输出这一行，不要解释：%s" % (MARKER, SETTLED)
    primary_text = (user_line + "\n" + MARKER + " file dependency check primary\n"
                    + "这一行用于 C-0 文件变更失效验证。\n")
    secondary_text = ("secondary marker file without the query sentence\n"
                      "canonical basis filler line\n")
    with open(os.path.join(ROOT_DIR, PRIMARY), "w") as f:
        f.write(primary_text)
    with open(os.path.join(ROOT_DIR, SECONDARY), "w") as f:
        f.write(secondary_text)
    results["root"] = {
        "dir": ROOT_DIR,
        "files_before": {
            PRIMARY: hashlib.sha256(primary_text.encode()).hexdigest(),
            SECONDARY: hashlib.sha256(secondary_text.encode()).hexdigest(),
        },
    }
    status, body, secs = request("PUT", "/v1/simigo/roots", {"path": ROOT_DIR})
    results["root"]["register"] = {
        "status": status, "seconds": secs, "body": body}
    if status != 200 or not body.get("root_id"):
        fail("ROOT_REGISTER_FAILED", body)
    results["root"]["root_id"] = body["root_id"]
    log("root registered %s" % body["root_id"])
    save()

    # ---- 2. one real-model chat generation bound to our file ----
    known = [r["settlement_id"]
             for r in db_rows("SELECT settlement_id FROM settlements;")]
    source = window(
        "source-chat-generation",
        {
            "model": model_id,
            "session_id": "c0-source-" + NONCE,
            "max_tokens": 96,
            "messages": [
                {"role": "system",
                 "content": "你是精确的标记输出器，只输出用户要求的那一行。"},
                {"role": "user", "content": user_line},
            ],
        },
        path="/v1/chat/completions")
    if source["status"] != 200:
        fail("SOURCE_GENERATION_FAILED", source["body"])

    # Poll for the new chat settlement (the settle step is post-response).
    row = None
    deadline = time.time() + 30
    while time.time() < deadline and row is None:
        for r in db_rows(
                "SELECT settlement_id, state_id, validation_status, validity "
                "FROM settlements WHERE settlement_id NOT IN (%s) "
                "AND state_id LIKE 'chat-%%';"
                % ",".join(["?"] * len(known)), tuple(known)):
            row = r
        if row is None:
            time.sleep(1)
    if row is None:
        fail("NO_SOURCE_SETTLEMENT")
    source_id = row["settlement_id"]
    inspected = tool("status", source_id)
    value = (inspected.get("content") or "").strip()
    choices = source["body"].get("choices") or []
    generated_text = ((choices[0].get("message") or {}).get("content") or "") \
        if choices else ""
    results["source"] = {
        "settlement_id": source_id,
        "state_id": row["state_id"],
        "validation_status": row["validation_status"],
        "validity": row["validity"],
        "generated_text": generated_text,
        "settled_value": value,
        "expected_value": SETTLED,
        "value_equals_expected": value == SETTLED,
        "payload_digest_ok": inspected.get("payload_digest_ok"),
        "payload_digest": inspected.get("payload_digest"),
        "bindings": inspected.get("bindings"),
        "usage": source["body"].get("usage"),
    }
    # The settled value only has to be the non-empty, digest-verified output of
    # THIS generation; its exact wording is the model's, not a probe criterion.
    if not value or not inspected.get("payload_digest_ok"):
        fail("SOURCE_SETTLEMENT_UNUSABLE", results["source"])
    results["directories_after_source"] = two_dirs()
    save()

    # ---- 3. the retrieval chain must exist and bind OUR file ----
    closure = db_rows("""
    WITH RECURSIVE up(id) AS (
      SELECT d.to_settlement FROM dependency_edges d WHERE d.from_settlement=?
      UNION
      SELECT d.to_settlement FROM dependency_edges d JOIN up u
        ON d.from_settlement=u.id)
    SELECT u.id AS settlement_id, s.validity, s.validation_status,
      (SELECT COUNT(*) FROM settlement_bindings b
        WHERE b.settlement_id=u.id AND b.source_file_id IS NOT NULL)
        AS file_bindings
    FROM up u LEFT JOIN settlements s ON s.settlement_id=u.id;
    """, (source_id,))
    retrieval = next((r for r in closure
                      if r["settlement_id"].startswith("is-retrieval:")), None)
    if retrieval is None:
        fail("NO_INFORMATION_DEMAND_EDGE", closure)
    bound = db_rows("""
    SELECT f.root_id, f.relative_path,
           substr(fc.content_sha256,1,16) AS sha16
    FROM settlement_bindings b
    JOIN external_files f
      ON f.file_id=b.source_file_id AND f.root_id=b.source_root_id
    LEFT JOIN file_contents fc
      ON fc.root_id=f.root_id AND fc.relative_path=f.relative_path
    WHERE b.settlement_id=?;
    """, (retrieval["settlement_id"],))
    ours = [b for b in bound if b["root_id"] == results["root"]["root_id"]]
    if not ours:
        fail("OUR_FILE_NOT_BOUND", {"closure": closure, "bound": bound})
    results["chain"] = {
        "upstream_closure": closure,
        "retrieval_settlement_id": retrieval["settlement_id"],
        "bound_files": bound,
        "our_bindings": ours,
    }
    log("chain: %s -> %s (%d bindings, %d ours)"
        % (source_id[:8], retrieval["settlement_id"][:20], len(bound), len(ours)))
    save()

    # ---- 4. reusable contract + positive zero-call consumption ----
    demand = tool("demand", QUERY, results["root"]["root_id"])
    declaration = tool("declare", source_id, QUERY, results["root"]["root_id"])
    if declaration.get("canonical_digest") != demand.get("digest"):
        fail("DECLARATION_DIGEST_MISMATCH", {"declaration": declaration,
                                             "demand": demand})
    results["contract"] = {
        "query": QUERY,
        "roots": [results["root"]["root_id"]],
        "canonical_entries": demand.get("entries"),
        "canonical": demand.get("canonical"),
        "canonical_digest": demand.get("digest"),
        "declaration": declaration,
    }
    save()

    positive = window(
        "consume-positive", consumption_body(model_id, source_id))
    receipt = (positive["body"].get("settlement_consumption") or {})
    results["consumers"] = {"positive": receipt}
    if positive["status"] != 200 or receipt.get("model_calls") != 0 \
            or receipt.get("outcome") != "consumed":
        fail("POSITIVE_CONSUMPTION_FAILED", positive["body"])
    if positive["generation_lines"]:
        fail("POSITIVE_CONSUMPTION_RAN_MODEL", positive["generation_lines"])
    if (receipt.get("consumption_id") is None
            or receipt.get("consumer_settlement_id") is None):
        fail("POSITIVE_CONSUMPTION_INCOMPLETE", receipt)
    output_text = ""
    for item in positive["body"].get("output") or []:
        for piece in item.get("content") or []:
            if isinstance(piece, dict) and piece.get("type") == "output_text":
                output_text += piece.get("text") or ""
    results["consumers"]["positive_output_text"] = output_text
    if output_text.strip() != value:
        fail("POSITIVE_CONSUMPTION_VALUE_MISMATCH",
             {"output": output_text, "settled_value": value})
    consumer_settlement = receipt["consumer_settlement_id"]
    log("positive consumption %s value ok" % receipt["consumption_id"])
    save()

    # ---- 5. mutate OUR file only, then re-scan via the production entry ----
    changed_text = (primary_text
                    + "\n" + MARKER + " CONTENT-CHANGED-" + NONCE + "\n")
    with open(os.path.join(ROOT_DIR, PRIMARY), "w") as f:
        f.write(changed_text)
    results["file_change"] = {
        "file": PRIMARY,
        "sha256_before": hashlib.sha256(primary_text.encode()).hexdigest(),
        "sha256_after": hashlib.sha256(changed_text.encode()).hexdigest(),
        "changed_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }
    before_rescan = counts()
    status, body, secs = request("PUT", "/v1/simigo/roots", {"path": ROOT_DIR})
    results["rescan"] = {
        "status": status, "seconds": secs, "body": body,
        "counts_before": before_rescan, "counts_after": counts(),
    }
    if status != 200:
        fail("RESCAN_FAILED", body)
    if not (body.get("content_settle") or {}).get("changed"):
        fail("RESCAN_SAW_NO_CHANGE", body)

    # ---- 6. invalidation state, from the authoritative store ----
    state = {
        "source": db_one(
            "SELECT validity, invalidated_at FROM settlements WHERE settlement_id=?;",
            (source_id,)),
        "consumer": db_one(
            "SELECT validity, invalidated_at FROM settlements WHERE settlement_id=?;",
            (consumer_settlement,)),
        "retrieval_row": db_one(
            "SELECT demand_id, status FROM retrieval_settlements "
            "WHERE bridged_settlement_id=?;", (retrieval["settlement_id"],)),
        "retrieval_closure": db_rows("""
        WITH RECURSIVE up(id) AS (
          SELECT d.to_settlement FROM dependency_edges d WHERE d.from_settlement=?
          UNION
          SELECT d.to_settlement FROM dependency_edges d JOIN up u
            ON d.from_settlement=u.id)
        SELECT u.id AS settlement_id, s.validity
        FROM up u LEFT JOIN settlements s ON s.settlement_id=u.id;
        """, (source_id,)),
        "consumptions": db_rows(
            "SELECT consumption_id, source_settlement_id, consumer_state_id, "
            "consumer_settlement_id, model_calls FROM settlement_consumptions;"),
    }
    results["invalidation"] = state
    save()
    if state["source"]["validity"] != "invalid":
        fail("SOURCE_NOT_INVALIDATED", state)
    if state["retrieval_row"] and state["retrieval_row"]["status"] != "invalidated":
        fail("RETRIEVAL_NOT_INVALIDATED", state["retrieval_row"])
    log("source invalidated at %s" % state["source"]["invalidated_at"])

    # ---- 7. attempted consumption after the change (the reading under test) ----
    ledger_before = counts()
    refused = window(
        "consume-after-change", consumption_body(model_id, source_id))
    ledger_after = counts()
    results["refusal_plain"] = {
        "status": refused["status"],
        "error": refused["error"],
        "ledger_before": ledger_before,
        "ledger_after": ledger_after,
        "no_model_call": not refused["generation_lines"],
        "no_new_consumption_row":
            ledger_before["consumptions"] == ledger_after["consumptions"],
        "no_new_settlement":
            ledger_before["settlements"] == ledger_after["settlements"],
        "no_new_state": ledger_before["states"] == ledger_after["states"],
    }
    recompute = window(
        "consume-after-change-recompute",
        consumption_body(model_id, source_id, allow_recompute=True))
    results["refusal_recompute"] = {
        "status": recompute["status"],
        "error": recompute["error"],
        "ledger_after": counts(),
        "no_model_call": not recompute["generation_lines"],
    }
    save()

    # ---- 8. close-out: directories with attribution, ledger, backup ----
    after = two_dirs()
    gen_start = source["t_start"] - 2.0
    gen_end = source["t_end"] + 2.0
    attribution = {}
    for name in ("prefix_pool", "branch_checkpoints"):
        base_rows = listing_rows(results["baseline"]["directories"][name])
        gen_rows = listing_rows(results["directories_after_source"][name])
        final_rows = listing_rows(after[name])
        added = sorted(set(gen_rows) - set(base_rows))
        removed = sorted(set(base_rows) - set(gen_rows))
        per_file = {}
        for rel in added:
            rows = [gen_rows[rel]]
            per_file[rel] = {
                "mtime_epoch": round(rows[0]["mtime_ns"] / 1e9, 3),
                "size": rows[0]["size"],
                "inside_source_generation_window": bool(
                    gen_start <= rows[0]["mtime_ns"] / 1e9 <= gen_end),
                "names_source_session": ("c0-source-" + NONCE) in rel,
            }
        attribution[name] = {
            "added_during_source_generation": added,
            "removed_during_source_generation": removed,
            "added_attribution": per_file,
            "all_added_attributable": all(
                v["inside_source_generation_window"]
                or v["names_source_session"]
                for v in per_file.values()),
            "zero_call_windows_left_it_unchanged": (
                results["directories_after_source"][name]["listing_sha256"]
                == after[name]["listing_sha256"]),
        }
    results["close_out"] = {
        "directories": after,
        "source_generation_window": {"t_start": gen_start, "t_end": gen_end},
        "attribution": attribution,
        "counts_final": counts(),
        "db_backup": backup_db("post"),
        "root_files": {
            PRIMARY: hashlib.sha256(changed_text.encode()).hexdigest(),
            SECONDARY: hashlib.sha256(secondary_text.encode()).hexdigest(),
        },
    }

    checks = {
        "source_invalidated": state["source"]["validity"] == "invalid",
        "retrieval_invalidated_status": bool(
            state["retrieval_row"]
            and state["retrieval_row"]["status"] == "invalidated"),
        "consumer_settlement_cascaded": (
            state["consumer"] or {}).get("validity") == "invalid",
        "refusal_ran_no_model": results["refusal_plain"]["no_model_call"],
        "refusal_left_no_consumption_row":
            results["refusal_plain"]["no_new_consumption_row"],
        "refusal_left_no_settlement":
            results["refusal_plain"]["no_new_settlement"],
        "refusal_left_no_state":
            results["refusal_plain"]["no_new_state"],
        "recompute_ran_no_model": results["refusal_recompute"]["no_model_call"],
        "prefix_pool_stable_across_zero_call_windows":
            attribution["prefix_pool"]["zero_call_windows_left_it_unchanged"],
        "checkpoints_stable_across_zero_call_windows":
            attribution["branch_checkpoints"]["zero_call_windows_left_it_unchanged"],
        "prefix_pool_changes_attributable_to_source_generation":
            attribution["prefix_pool"]["all_added_attributable"],
        "checkpoints_changes_attributable_to_source_generation":
            attribution["branch_checkpoints"]["all_added_attributable"],
        "no_kv_files_removed": not (
            attribution["prefix_pool"]["removed_during_source_generation"]
            or attribution["branch_checkpoints"]["removed_during_source_generation"]),
    }
    contract_shape = {
        "expected_status": 422,
        "expected_error_kind": "SETTLEMENT_CONSUMPTION_REFUSED",
        "expected_reason_code": "source_not_valid",
        "actual_status": refused["status"],
        "actual_error_kind": refused["error"]["error_kind"],
        "actual_reason_code": refused["error"]["reason_code"],
    }
    contract_shape["matches_contract"] = (
        contract_shape["actual_status"] == contract_shape["expected_status"]
        and contract_shape["actual_error_kind"]
        == contract_shape["expected_error_kind"]
        and contract_shape["actual_reason_code"]
        in ("source_not_valid", "dependency_invalid"))
    results["checks"] = checks
    results["contract_shape"] = contract_shape
    results["verdict"] = {
        "invalidation_chain_proven": all(checks.values()),
        "terminal_matches_declared_contract": contract_shape["matches_contract"],
        "note": ("pre-fix reading: admission-stage refusal is expected to be "
                 "classified as 500 engine instead of 422 source_not_valid"),
    }
    path = save()
    log("checks=%s" % json.dumps(checks))
    log("terminal=%s/%s contract_match=%s"
        % (contract_shape["actual_status"],
           contract_shape["actual_reason_code"],
           contract_shape["matches_contract"]))
    log("evidence %s" % path)
    if not all(checks.values()):
        raise SystemExit(2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
