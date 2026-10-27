#!/usr/bin/env python3
"""Stage 3 / K3: interrupt a real model call in the G phase -> the partial output
must form no valid settlement -> after process restart, re-execute from the
nearest qualified anchor until exactly one valid settlement exists, while both KV
carriers stay unreadable and unwritable.

  --phase a  settle an anchor turn, then start a long streamed generation in the
             same session and hard-close the socket (SO_LINGER 0 -> RST) mid
             stream. Record the partial output and the ledger state.
  --phase b  after the user quits and relaunches: re-run the interrupted demand
             from the anchor and prove exactly one valid settlement, the recovery
             source, and that the unfinished output never entered the new input.
"""
import argparse, json, os, socket, struct, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stage3_common as C
from k2_probe import ensure_block

TAG = "K3"
STATE = "state-K3.json"
ITEMS = 30


def streamed_interrupt(model_id, session_id, prompt, max_tokens, want_chunks):
    """POST a streaming chat request and hard-close mid-stream (RST)."""
    body = json.dumps({"model": model_id, "session_id": session_id,
                       "max_tokens": max_tokens, "stream": True,
                       "messages": [{"role": "system",
                                     "content": "你是精确的编号输出器，逐行输出用户要求的编号，不要解释。"},
                                    {"role": "user", "content": prompt}]}).encode()
    head = ("POST /v1/chat/completions HTTP/1.1\r\nHost: 127.0.0.1:8000\r\n"
            "Content-Type: application/json\r\nContent-Length: %d\r\n\r\n"
            % len(body)).encode()
    s = socket.create_connection(("127.0.0.1", 8000), timeout=300)
    s.sendall(head + body)
    off_before = C.trace_offset()
    buf = b""
    pieces = []
    chunks = 0
    t0 = time.time()
    while chunks < want_chunks and time.time() - t0 < 180:
        try:
            data = s.recv(65536)
        except Exception as e:
            break
        if not data:
            break
        buf += data
        while b"\r\n\r\n" not in buf and b"\n\n" not in buf:
            pass
        # parse SSE delta texts from whatever complete events are in buf
        text = buf.decode(errors="replace")
        for line in text.splitlines():
            if line.startswith("data:") and line.strip() not in ("data: [DONE]",):
                try:
                    obj = json.loads(line[5:].strip())
                except Exception:
                    continue
                for choice in obj.get("choices") or []:
                    delta = (choice.get("delta") or {}).get("content")
                    if delta:
                        chunks += 1
                        pieces.append(delta)
        buf = b""
    # hard close: send RST so the server sees an abrupt disconnect
    try:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER,
                     struct.pack("ii", 1, 0))
    except Exception:
        pass
    s.close()
    time.sleep(0.4)
    return {"partial_text": "".join(pieces), "chunk_count": chunks,
            "seconds": round(time.time() - t0, 3),
            "trace_raw": C.trace_since(off_before),
            "generation_lines": C.generation_lines(C.trace_since(off_before)),
            "kv_lines": C.kv_lines(C.trace_since(off_before))}


def session_view(session_id):
    return {
        "chat_messages": C.db_rows(
            "SELECT id, session_id, role, length(content) AS content_len, "
            "content_sha256, content_object_id, created_at FROM chat_messages "
            "WHERE session_id=? ORDER BY id;", (session_id,)),
        "message_object_contents": [
            {"object_id": m["content_object_id"],
             "content": (C.db_one(
                 "SELECT content FROM is_objects WHERE object_id=?;",
                 (m["content_object_id"],)) or {}).get("content")}
            for m in C.db_rows(
                "SELECT content_object_id FROM chat_messages WHERE session_id=? "
                "ORDER BY id;", (session_id,))],
        "execution_states": C.db_rows(
            "SELECT state_id, parent_id, model_identity, position, "
            "continuation_id, anchor, lifecycle, created_at FROM execution_states "
            "WHERE state_id IN (SELECT state_id FROM settlements WHERE 1) "
            "OR state_id LIKE 'chat-%' ORDER BY created_at;"),
        "settlements": C.settlement_rows(),
    }


def phase_a():
    state2 = C.read_state("state-K2.json")
    nonce = time.strftime("%Y%m%d-%H%M%S")
    res = C.new_results("K3a", nonce)
    app = C.app_state()
    res["app_state"] = app
    model_id = C.wait_ready()
    res["model_id"] = model_id
    res["block_check"] = ensure_block(TAG, res)
    res["counters_before"] = C.db_counters()
    session = "k3-source-%s" % nonce
    res["session_id"] = session
    res["carried_from_k2"] = {"nonce": state2["nonce"],
                              "source_settlement": state2["source"]["settlement_id"]}
    C.log(TAG, "phase a pid=%s session=%s" % (app["pids"], session))

    anchor = C.settle_source(res, TAG, model_id, nonce, "k3")
    res["anchor"] = anchor
    C.save(res)

    prompt = ("请逐行输出编号序列 %s 到 %s，每行一个，不要解释。"
              % ("INT-A01-%s" % nonce, "INT-A%02d-%s" % (ITEMS, nonce)))
    res["interrupted_prompt"] = prompt
    it = streamed_interrupt(model_id, session, prompt, 400, 8)
    res["interrupted"] = it
    C.log(TAG, "interrupted after %d chunks, %d chars"
          % (it["chunk_count"], len(it["partial_text"])))
    snap0 = session_view(session)
    res["session_immediately_after_interrupt"] = snap0
    time.sleep(3.0)
    snap1 = session_view(session)
    res["session_3s_after_interrupt"] = snap1
    res["counters_after_interrupt"] = C.db_counters()
    res["counter_delta_after_interrupt"] = {
        k: res["counters_after_interrupt"][k] - res["counters_before"][k]
        for k in res["counters_after_interrupt"]}
    anchor_row = next(r for r in snap1["settlements"]
                      if r["settlement_id"] == anchor["settlement_id"])
    res["anchor_row"] = anchor_row
    res["rows_with_a_valid_settlement_after_interrupt"] = [
        r for r in snap1["settlements"] if r["validation_status"] == "VALID"]
    res["block_enforced_at_end"] = C.block_enforced()[0]
    res["cache_at_end"] = C.cache_root_state()
    res["sweep_for_redirected_kv"] = C.sweep_kv_paths()
    res["real_home_after"] = C.real_home_state()
    C.save(res)
    C.write_state(STATE, {"nonce": nonce, "session_id": session,
                          "prompt": prompt, "anchor": anchor,
                          "partial_text": it["partial_text"],
                          "chunk_count": it["chunk_count"],
                          "interrupted_trace_raw": it["trace_raw"],
                          "phase_a_pids": app["pids"],
                          "settlement_ids_after_a":
                              [r["settlement_id"] for r in snap1["settlements"]],
                          "message_objects_after_a":
                              snap1["message_object_contents"]})
    C.log(TAG, "phase a done: partial=%r settled_rows_delta=%s"
          % (it["partial_text"][-60:], res["counter_delta_after_interrupt"]))


def phase_b():
    state = C.read_state(STATE)
    nonce, session = state["nonce"], state["session_id"]
    res = C.new_results("K3b", nonce)
    app = C.app_state()
    res["app_state_after_restart"] = app
    res["carried"] = {k: state[k] for k in
                      ("nonce", "session_id", "prompt", "phase_a_pids",
                       "settlement_ids_after_a")}
    model_id = C.wait_ready()
    res["model_id"] = model_id
    res["block_check"] = ensure_block(TAG, res)
    res["counters_before"] = C.db_counters()
    res["session_view_before_rerun"] = session_view(session)
    ids_before = {r["settlement_id"] for r in C.settlement_rows()}
    res["real_home_before"] = C.real_home_state()
    C.save(res)
    C.log(TAG, "phase b pid=%s (phase a pid=%s)" % (app["pids"], state["phase_a_pids"]))

    off = C.trace_offset()
    rerun = C.window(res, TAG, "rerun-from-anchor",
                     {"model": model_id, "session_id": session, "max_tokens": 400,
                      "messages": [{"role": "system",
                                    "content": "你是精确的编号输出器，逐行输出用户要求的编号，不要解释。"},
                                   {"role": "user", "content": state["prompt"]}]},
                     path="/v1/chat/completions")
    time.sleep(2.0)
    res["rerun_trace_raw"] = rerun["trace_raw"]
    view = session_view(session)
    res["session_view_after_rerun"] = view
    new_rows = [r for r in view["settlements"]
                if r["settlement_id"] not in ids_before]
    res["new_settlement_rows"] = new_rows
    valid_new = [r for r in new_rows if r["validation_status"] == "VALID"]
    res["counters_after"] = C.db_counters()
    res["counter_delta"] = {k: res["counters_after"][k] - res["counters_before"][k]
                            for k in res["counters_after"]}
    res["block_enforced_at_end"] = C.block_enforced()[0]
    res["cache_at_end"] = C.cache_root_state()
    res["sweep_for_redirected_kv"] = C.sweep_kv_paths()
    res["real_home_after"] = C.real_home_state()

    partial = state["partial_text"]
    # the partial's own item list, to look for it inside the new input snapshot
    items_in_partial = [ln.strip() for ln in partial.splitlines() if ln.strip()]
    input_objects = [o for o in view["message_object_contents"]
                     if o["object_id"] not in
                     {m["object_id"] for m in
                      res["session_view_before_rerun"]["message_object_contents"]}]
    res["new_message_objects"] = input_objects
    rerun_input_text = "\n".join(str((o["content"] or b"").decode(errors="replace")
                                     if isinstance(o["content"], bytes)
                                     else (o["content"] or ""))
                                 for o in res["session_view_before_rerun"]
                                 ["message_object_contents"])
    checks = {
        "process_restarted": app["pids"] != state["phase_a_pids"],
        "block_enforced_start": "enforced_after_repair" in res["block_check"]
            or res["block_check"].get("enforced_before_repair"),
        "block_enforced_end": res["block_enforced_at_end"],
        "no_kv_files_created": not res["cache_at_end"]["children"]["prefix-pool"]["present"]
            and not res["cache_at_end"]["children"]["branch-checkpoints"]["present"],
        "no_kv_redirection": not [f for f in res["sweep_for_redirected_kv"]
                                  if f["where"] == "run-tree"],
        "real_home_untouched": res["real_home_before"] == res["real_home_after"],
        "rerun_200": rerun["status"] == 200,
        "rerun_complete_sequence": all(
            ("INT-A%02d-%s" % (i, nonce)) in C.output_text(rerun["body"])
            for i in range(1, ITEMS + 1)),
        "exactly_one_new_valid_settlement": len(valid_new) == 1,
        "rerun_model_work_recorded": bool(rerun["generation_lines"]),
        "no_kv_restore_lines": not [ln for ln in rerun["trace_raw"].splitlines()
                                    if "cacheLoad" in ln or "poolBind" in ln
                                    or "estored" in ln],
        "partial_never_entered_new_input": all(
            item not in rerun_input_text for item in items_in_partial[-3:])
            if items_in_partial else True,
    }
    res["items_in_partial"] = items_in_partial
    res["rerun_input_text_len"] = len(rerun_input_text)
    res["checks"] = checks
    res["summary"] = {"passed": sum(1 for v in checks.values() if v),
                      "total": len(checks),
                      "failures": [k for k, v in checks.items() if not v]}
    C.save(res)
    C.log(TAG, "phase b checks %d/%d failures=%s"
          % (res["summary"]["passed"], res["summary"]["total"],
             res["summary"]["failures"]))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", choices=["a", "b"], required=True)
    a = ap.parse_args()
    phase_a() if a.phase == "a" else phase_b()
