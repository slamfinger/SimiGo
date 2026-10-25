#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
R3-2 campaign setup — one-shot, per design §1a (H-A campaign setup lock).

  ① (ES, IS₀) selected once by pre-registered criteria (selection does not
     depend on any t₀ result);
  ② t₀ judged once: Cons = R2 rev.2 candidate, per R3-1 Spec rev.2
     procedures, at campaign setup (before any ΔIS exists);
  ③ binary & final: true ⇒ validity fixed campaign-wide; false ⇒
     setup INVALID + records preserved + STOP (re-setup requires a new
     human authorization);
  ④ per-cell t₀ re-evaluation (in run_cells) = instrument-consistency
     replication.

Setup record pins the three elements: Cons version / judgment rule /
judgment time, plus artifact hashes and the harness SHA-256.
"""

import datetime
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r32_lib as L

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SEALED = os.path.join(REPO, "docs", "02-evidence", "rc1-attempt4",
                      "RC1-A4-20261003T040749Z-57375")
EVIDENCE_ROOT = os.path.join(REPO, "docs", "02-evidence", "r3-2-execution")


def utc_now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc) \
        .strftime("%Y-%m-%dT%H:%M:%SZ")


def main() -> int:
    run_uuid = "R32-" + datetime.datetime.now(datetime.timezone.utc) \
        .strftime("%Y%m%dT%H%M%SZ") + "-" + str(os.getpid())
    run_dir = os.path.join(EVIDENCE_ROOT, run_uuid)
    os.makedirs(run_dir, exist_ok=True)
    log_path = os.path.join(run_dir, "observations.jsonl")

    def obs(event, **kw):
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps({"run_uuid": run_uuid, "event": event,
                                "monotonic": round(__import__("time").monotonic(), 6),
                                "wall_utc": utc_now_iso(), **kw},
                               ensure_ascii=False, sort_keys=True) + "\n")

    obs("setup_started", run_dir=run_dir)

    # --- ① (ES, IS₀) selection — pre-registered criteria, no t₀ dependence --
    selection_criteria = {
        "es_formation": "formed by r32-formation-v1 against canonical IS0 "
                        "(digests computed from actual bytes; no hand-written "
                        "baselines — no construct-then-claim)",
        "lineage": "transported from sealed R-C1 attempt #4 evidence "
                   "(RC1-A4-20261003T040749Z-57375, C-B arm) — real prior "
                   "research artifacts, transport-not-construct (D6)",
        "formation_materials_required": ["I-EV declarations",
                                         "A anchor reference + formation "
                                         "digest", "C prerequisites + "
                                         "declared mechanical conditions"],
        "anchor_reference_form": "symbolic (design §2.5)",
    }

    # --- canonical IS₀ construction (campaign setup material) ------------
    is0 = os.path.join(run_dir, "is0-canonical")
    os.makedirs(os.path.join(is0, "objects"), exist_ok=True)
    os.makedirs(os.path.join(is0, "runtime"), exist_ok=True)
    os.makedirs(os.path.join(is0, "lineage"), exist_ok=True)
    os.makedirs(os.path.join(is0, "archive"), exist_ok=True)

    # transport real sealed R-C1 #4 content (bytes from sealed artifacts)
    with open(os.path.join(SEALED, "runs", "C-B", "declared", "s0.json"),
              "rb") as f:
        s0_bytes = f.read()
    with open(os.path.join(SEALED, "runs", "C-B", "declared", "s1.json"),
              "rb") as f:
        s1_bytes = f.read()
    with open(os.path.join(SEALED, "runs", "C-B", "declared",
                           "task-charter.json"), "rb") as f:
        charter = json.loads(f.read())
    lineage_manifest_sha = L.sha256_file(os.path.join(SEALED,
                                                      "evidence-sha256.txt"))

    L.write_json(os.path.join(is0, "manifest.json"), {
        "scope_tags": ["r3-2-campaign"],
        "in_scope": ["objects/", "runtime/", "lineage/", "archive/"],
        "out_of_scope": [],
        "access_denied": [],
    })
    L.save_index(is0, {
        "runtime-declaration": ["runtime/runtime-declaration.json"],
        "lineage-root": ["lineage/lineage-root.json"],
        "I-S0": ["objects/I-S0.json"],
        "I-S1": ["objects/I-S1.json"],
        "anchor:state-diff": ["objects/R-1.json"],
        "unreferenced-1": ["objects/unreferenced-1.json"],
        "archived-note": ["archive/archived-note.json"],
    })
    L.save_invalidation(is0, {"records": []})
    L.write_json(os.path.join(is0, "runtime/runtime-declaration.json"),
                 {"fixture_class": "r3-2-minimal-v1"})
    L.write_json(os.path.join(is0, "lineage/lineage-root.json"), {
        "derived_from": "R-C1-A4-RC1-A4-20261003T040749Z-57375 (C-B arm)",
        "evidence_manifest_sha256": lineage_manifest_sha,
        "note": "ES lineage transported from sealed R-C1 attempt #4 evidence",
    })
    L.write_json(os.path.join(is0, "objects/I-S0.json"), {
        "id": "I-S0",
        "content": json.loads(s0_bytes.decode("utf-8")),
        "source": "R-C1-A4 C-B declared/s0.json (sealed)",
    })
    L.write_json(os.path.join(is0, "objects/I-S1.json"), {
        "id": "I-S1",
        "content": json.loads(s1_bytes.decode("utf-8")),
        "source": "R-C1-A4 C-B declared/s1.json (sealed)",
    })
    r1 = {
        "id": "R-1",
        "content": {
            "settled_diff": {"alpha": {"from": 17, "to": 42},
                             "mode": {"from": "quiet", "to": "active"}},
            "next_action": charter["continuationRule"]["action"],
            "basis": "task %s charter: alphaMinimum=%s, requiredMode=%s; "
                     "S1 satisfies both" % (charter["taskID"],
                                            charter["continuationRule"]["alphaMinimum"],
                                            charter["continuationRule"]["requiredMode"]),
        },
        "source": "R-C1-A4 C-B evaluation.json X-1..X-5 verified (sealed)",
    }
    L.write_json(os.path.join(is0, "objects/R-1.json"), r1)
    L.write_json(os.path.join(is0, "objects/unreferenced-1.json"), {
        "id": "U-1", "content": "unreferenced campaign note (K-1a/B cells)"})
    L.write_json(os.path.join(is0, "archive/archived-note.json"), {
        "id": "ARCH-1", "content": "archived note (B region cells)"})

    is0_sha = L.sha256_dir(is0)
    obs("is0_constructed", is0_sha256=is0_sha)

    # --- ES formation procedure (digests computed from actual IS0 bytes) ---
    payload = {
        "task": charter,
        "continuation_position": {
            "after_state": "I-S1",
            "basis": "R-C1 C-B staged pointer set [progress, s0, s1, task]",
        },
    }
    es = {
        "es_schema": "r3-2-es-v1",
        "formation": {
            "procedure": "r32-formation-v1",
            "formed_at_utc": utc_now_iso(),
            "transport_source": "R-C1-A4 sealed evidence (lineage via I-EV-2)",
            "note": "formation executed against canonical IS0; all baselines "
                    "computed from actual bytes (ES-artifact-resident, §2a)",
        },
        "payload": payload,
        "I_ev": {
            "I-EV-1": {"role": "I-1 model/fixture binding",
                       "self_declaration": {"fixture_class":
                                            "r3-2-minimal-v1"},
                       "is_reference": {"key": "runtime-declaration",
                                        "field": "fixture_class"}},
            "I-EV-2": {"role": "I-2 lineage binding",
                       "is_reference": {"key": "lineage-root"}},
            "I-EV-3": {"role": "I-3 payload integrity",
                       "payload_sha256": L.sha256_canonical(payload)},
        },
        "A_ev": {
            "role": "A-1 content binding",
            "anchor_name": "anchor:state-diff",
            "reference_form": "symbolic",
            "formation_target_content_sha256":
                L.sha256_file(os.path.join(is0, "objects/R-1.json")),
        },
        "C_ev": {
            "role": "C-1 continuation permission prerequisites",
            "prerequisite_keys": ["I-S0", "I-S1"],
            "declared_conditions": [
                {"type": "scope-tag", "value": "r3-2-campaign"},
                {"type": "validity",
                 "not_after": (datetime.datetime.now(datetime.timezone.utc)
                               + datetime.timedelta(days=30))
                              .strftime("%Y-%m-%dT%H:%M:%SZ")},
                {"type": "dependency-reference", "keys": ["I-S0", "I-S1"]},
            ],
        },
    }
    es_path = os.path.join(run_dir, "es-artifact.json")
    L.write_json(es_path, es)
    es_sha = L.sha256_file(es_path)
    obs("es_formed", es_artifact_sha256=es_sha)

    # --- ② one-shot t₀ judgment (Spec rev.2 procedures, setup stage) -------
    setup_pinned_ts = utc_now_iso()
    t0 = L.eval_cons(es, is0, setup_pinned_ts, mode="setup")
    obs("t0_evaluated", result=t0)

    cons_true = (t0["cons"] == "SATISFIED"
                 and all(t0[k]["state"] == "SATISFIED" for k in ("I", "A", "C")))

    setup_record = {
        "run_uuid": run_uuid,
        "design_source": "SIMIGO_LAB_R3_2_DESIGN_20261003.md (rev.2, RATIFIED)",
        "judgment_rule": {
            "cons_version": "R2 rev.2 candidate: Cons(ES,IS) ⟺ "
                            "I-condition ∧ A-condition ∧ C-condition",
            "spec": "SIMIGO_LAB_R3_1_JUDGMENT_SPECIFICATION_20261003.md "
                    "(rev.2, RATIFIED)",
            "judgment_time": "campaign setup stage, before any ΔIS exists",
        },
        "selection_criteria": selection_criteria,
        "setup_pinned_timestamp": setup_pinned_ts,
        "es_artifact_sha256": es_sha,
        "is0_canonical_sha256": is0_sha,
        "harness": {
            "r32_lib_sha256": L.sha256_file(os.path.join(
                os.path.dirname(os.path.abspath(__file__)), "r32_lib.py")),
            "medium": "python3 stdlib only; zero model inference (design §1)",
        },
        "campaign_order": L.CAMPAIGN_ORDER,
        "t0_evaluation": t0,
        "validity": "VALID" if cons_true else "INVALID",
        "validity_rule": "design §1a: false ⇒ INVALID + preserve + STOP; "
                         "re-setup requires new human authorization",
    }
    L.write_json(os.path.join(run_dir, "setup_record.json"), setup_record)
    obs("setup_completed", validity=setup_record["validity"])

    print(json.dumps({"run_uuid": run_uuid, "validity":
                      setup_record["validity"], "t0": t0},
                     ensure_ascii=False, indent=2))
    return 0 if cons_true else 1


if __name__ == "__main__":
    sys.exit(main())
