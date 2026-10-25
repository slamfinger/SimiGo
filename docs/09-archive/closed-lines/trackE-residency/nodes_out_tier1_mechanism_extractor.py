#!/usr/bin/env python3
# Copyright © 2026 SimiGo-Lab. Nodes-out Tier-1 read-only mechanism extractor.
# Boundary: import unchanged Runner f4d880e; no policy/capacity/decision edit.

import json
import os
from collections import Counter, defaultdict

import nodes_out_experiment_runner as R


HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "runs", "NODES_OUT_TIER1_MECHANISM_20260922")
OFFICIAL_ARTIFACT = os.path.join(
    HERE, "runs", "NODES_OUT_RUNNER_AUDIT_20260922", "runner_audit.json")
RUNNER_PATH = os.path.join(HERE, "nodes_out_experiment_runner.py")
EXTRACTOR_REL = "trackE-residency/nodes_out_tier1_mechanism_extractor.py"
CONTRACT_COMMIT = "0918260c722a98a2c9b6ccaa94efb0ca9668d9ec"
RUNNER_COMMIT = "f4d880efd4cac21e60a55688dd686b801f3b7044"
NODE_KIB = R.GDN_KIB + R.ATT_KIB
UNIT_KIB = {"GDN": R.GDN_KIB, "ATT": R.ATT_KIB}


def mean(values):
    return round(sum(values) / len(values), 6) if values else 0


def step_summary(values):
    return {
        "sum": sum(values), "min": min(values), "max": max(values),
        "mean": mean(values), "terminal": values[-1],
    }


def candidate_event_summary(run):
    events = run.events
    rehy_units = Counter(unit[0] for op, _, unit, _ in events
                         if op == "rehydrate")
    ext_units = Counter(unit[0] for op, _, unit, _ in events
                        if op == "externalize")
    rehy_kib = sum(UNIT_KIB[unit[0]] for op, _, unit, _ in events
                   if op == "rehydrate")
    ext_kib = sum(UNIT_KIB[unit[0]] for op, _, unit, _ in events
                  if op == "externalize")
    final = run.final()
    return {
        "M08_raw_rehydrate_count": {
            "GDN": rehy_units["GDN"], "ATT": rehy_units["ATT"],
            "total": final["rehy_count"],
        },
        "M09_rehydrate_byte_mass_KiB": {
            "GDN": rehy_units["GDN"] * UNIT_KIB["GDN"],
            "ATT": rehy_units["ATT"] * UNIT_KIB["ATT"],
            "total": rehy_kib,
        },
        "M11_raw_externalize_count": {
            "GDN": ext_units["GDN"], "ATT": ext_units["ATT"],
            "total": final["ext_count"],
        },
        "M12_externalize_byte_mass_KiB": {
            "GDN": ext_units["GDN"] * UNIT_KIB["GDN"],
            "ATT": ext_units["ATT"] * UNIT_KIB["ATT"],
            "total": ext_kib,
        },
        "compatible_J_M13": round(
            R.C_EXT * final["ext_count"] + R.C_REHY * final["rehy_count"], 6),
        "terminal": final,
    }


def baseline_metrics(trace, states, metrics):
    resident_counts = [len(row["resident"]) for row in states]
    current_cover = [trace[i] in states[i]["resident"]
                     for i in range(len(trace))]
    prev_resident = set()
    acquisitions = []
    for step, node in enumerate(trace):
        acquisitions.append(node not in prev_resident)
        prev_resident = set(states[step]["resident"])
    full = resident_counts
    empty = [R.N_NODES - count for count in resident_counts]
    resident_kib = [count * NODE_KIB for count in resident_counts]
    return {
        "M02_decode_ready_or_baseline_current_resident": {
            "baseline_current_resident": {
                "true_steps": sum(current_cover),
                "false_steps": len(trace) - sum(current_cover),
            },
        },
        "M04_current_node_coverage": {
            "baseline": {
                "covered_steps": sum(current_cover),
                "uncovered_steps": len(trace) - sum(current_cover),
            },
        },
        "M05_residency_state_shape_mapped": {
            "note": ("baseline node state is mapped as full; partial is "
                     "not representable at node granularity"),
            "full_node_node_steps": step_summary(full),
            "partial_node_node_steps": step_summary([0] * len(trace)),
            "empty_node_node_steps": step_summary(empty),
            "externalized_node_node_steps": step_summary(
                [len(row["externalized"]) for row in states]),
            "terminal": {
                "resident": len(states[-1]["resident"]),
                "externalized": len(states[-1]["externalized"]),
            },
        },
        "M06_slot_occupancy_ratio": {
            "step_summary": step_summary(
                [count / R.B_NODES for count in resident_counts]),
            "capacity_exceed_steps": sum(
                count > R.B_NODES for count in resident_counts),
        },
        "M07_resident_byte_exposure_KiB": {
            "step_summary": step_summary(resident_kib),
            "unit": "KiB; disclosure only, capacity remains node-slot based",
        },
        "M08_raw_rehydrate_count": metrics["rehy"],
        "M09_rehydrate_byte_mass_KiB": metrics["rehy"] * NODE_KIB,
        "M10_node_touch_acquisition_incidence_mapped": {
            "acquisition_touches": sum(acquisitions),
            "no_acquisition_touches": len(trace) - sum(acquisitions),
            "note": ("step 0 uses an empty pre-state; later steps use the "
                     "prior post-capacity baseline resident set"),
        },
        "M11_raw_externalize_count": metrics["ext"],
        "M12_externalize_byte_mass_KiB": metrics["ext"] * NODE_KIB,
        "M13_compatible_J_disclosure": round(metrics["J"], 6),
    }


def candidate_metrics(trace, run):
    events = run.events
    by_step_rehy = {}
    events_by_step = defaultdict(list)
    for op, step, unit, _ in events:
        if op == "rehydrate":
            by_step_rehy.setdefault(step, set()).add(unit[0])
        events_by_step[step].append((op, unit))
    any_acq = [bool(by_step_rehy.get(step, set())) for step in range(len(trace))]
    full_pair = [by_step_rehy.get(step, set()) == {"GDN", "ATT"}
                 for step in range(len(trace))]

    full, partial, empty = [], [], []
    resident_units, resident_kib = [], []
    gdn_resident, att_resident = [], []
    unit_res = {(kind, node): False
                for node in range(R.N_NODES) for kind in UNIT_KIB}
    for step in range(len(trace)):
        for op, unit in events_by_step[step]:
            unit_res[unit] = op == "rehydrate"
        f = p = e = g = a = 0
        for node in range(R.N_NODES):
            is_gdn = unit_res[("GDN", node)]
            is_att = unit_res[("ATT", node)]
            g += is_gdn
            a += is_att
            if is_gdn and is_att:
                f += 1
            elif is_gdn or is_att:
                p += 1
            else:
                e += 1
        full.append(f)
        partial.append(p)
        empty.append(e)
        gdn_resident.append(g)
        att_resident.append(a)
        resident_units.append(g + a)
        resident_kib.append(g * UNIT_KIB["GDN"] + a * UNIT_KIB["ATT"])

    current_cover = list(run.decode_ready)
    result = candidate_event_summary(run)
    result.update({
        "M02_decode_ready_or_baseline_current_resident": {
            "candidate_decode_ready": {
                "true_steps": sum(current_cover),
                "false_steps": len(trace) - sum(current_cover),
            },
        },
        "M04_current_node_coverage": {
            "candidate_gdn_and_att": {
                "covered_steps": sum(current_cover),
                "uncovered_steps": len(trace) - sum(current_cover),
            },
        },
        "M05_residency_state_shape_mapped": {
            "full_node_node_steps": step_summary(full),
            "partial_node_node_steps": step_summary(partial),
            "empty_node_node_steps": step_summary(empty),
            "resident_units_by_kind_node_steps": {
                "GDN": step_summary(gdn_resident),
                "ATT": step_summary(att_resident),
            },
            "terminal": {
                "full_node": full[-1], "partial_node": partial[-1],
                "empty_node": empty[-1], "resident_units": resident_units[-1],
                "resident_units_by_kind": {
                    "GDN": gdn_resident[-1], "ATT": att_resident[-1]},
            },
        },
        "M06_slot_occupancy_ratio": {
            "step_summary": step_summary(
                [count / R.B_UNITS for count in resident_units]),
            "capacity_exceed_steps": sum(
                count > R.B_UNITS for count in resident_units),
        },
        "M07_resident_byte_exposure_KiB": {
            "step_summary": step_summary(resident_kib),
            "unit": "KiB; disclosure only, capacity remains unit-slot based",
        },
        "terminal_state_replay_matches_runner": (
            resident_units[-1] == run.final()["resident_units"]),
        "state_replay_source": "post-step replay of unchanged Runner events",
        "M10_node_touch_acquisition_incidence_mapped": {
            "any_unit_acquisition_touches": sum(any_acq),
            "full_pair_acquisition_touches": sum(full_pair),
            "no_acquisition_touches": len(trace) - sum(any_acq),
            "note": ("any/full-pair are Candidate-only mapped descriptors; "
                     "they are not equivalent to baseline node acquisition"),
        },
    })
    return result


def binding_checks(official, runs):
    checks = {
        "runner_commit": RUNNER_COMMIT,
        "contract_commit": CONTRACT_COMMIT,
        "runner_sha256": R.sha256_file(RUNNER_PATH),
        "official_artifact_sha256": R.sha256_file(OFFICIAL_ARTIFACT),
        "baseline_blob": R.BASELINE_BLOB,
        "runner_sha_matches_official": (
            R.sha256_file(RUNNER_PATH) == official["runner"]["sha256"]),
        "baseline_blob_matches_official": (
            R.BASELINE_BLOB == official["baseline"]["blob"]),
    }
    for name, item in runs.items():
        terminal = item["baseline_states"][-1]
        official_terminal = official["baseline"]["execution_state"][
            "by_workload"][name]["terminal"]
        checks[f"{name}_baseline_matches_official"] = (
            terminal["rehy_count"] == official_terminal["rehy_count"]
            and terminal["ext_count"] == official_terminal["ext_count"]
            and terminal["violations"] == official_terminal["violations"]
            and len(terminal["resident"]) == official_terminal["resident_count"])
        official_det = next(row for row in official["deterministic"]["run_1"]
                            if row["workload"] == name)
        checks[f"{name}_candidate_counts_match_official"] = (
            item["candidate_1"].final()["rehy_count"] == official_det["rehy_count"]
            and item["candidate_1"].final()["ext_count"] == official_det["ext_count"])
    return checks


def markdown_report(data):
    lines = [
        "# Nodes-out Tier-1 Mechanism Accounting Report v0.1", "",
        "**状态**：`MECHANISM ACCOUNTING COMPLETE / EFFECT VERDICT LOCKED`  ",
        "**边界**：按 Effect Interpretation Contract v0.1 只做机制账本；无性能 PASS/FAIL，无优劣结论，无跨粒度 raw count 比较。", "",
        "## Provenance", "",
        "| item | value |", "|---|---|",
        f"| Contract commit | `{data['provenance']['contract_commit']}` |",
        f"| Audited Runner commit | `{data['provenance']['runner_commit']}` |",
        f"| Baseline | `{data['provenance']['baseline_commit']}` |",
        f"| Baseline blob | `{data['provenance']['baseline_blob']}` |",
        f"| Runner SHA-256 | `{data['provenance']['runner_sha256']}` |",
        f"| Official artifact SHA-256 | `{data['provenance']['official_artifact_sha256']}` |",
        f"| Extractor SHA-256 | `{data['provenance']['extractor_sha256']}` |", "",
        "## Binding", "",
    ]
    for key, value in data["binding"].items():
        lines.append(f"- `{key}`: `{value}`")
    lines += ["", "## Per-workload mechanism ledger", ""]
    for name, item in data["workloads"].items():
        base, cand = item["baseline"], item["candidate"]
        base_shape = base["M05_residency_state_shape_mapped"]
        cand_shape = cand["M05_residency_state_shape_mapped"]
        base_occ = base["M06_slot_occupancy_ratio"]["step_summary"]
        cand_occ = cand["M06_slot_occupancy_ratio"]["step_summary"]
        base_kib = base["M07_resident_byte_exposure_KiB"]["step_summary"]
        cand_kib = cand["M07_resident_byte_exposure_KiB"]["step_summary"]
        lines += [
            f"### {name}", "",
            "| metric | baseline | Candidate A |", "|---|---:|---:|",
            f"| M02 covered steps | {base['M02_decode_ready_or_baseline_current_resident']['baseline_current_resident']['true_steps']} | {cand['M02_decode_ready_or_baseline_current_resident']['candidate_decode_ready']['true_steps']} |",
            f"| M04 covered steps | {base['M04_current_node_coverage']['baseline']['covered_steps']} | {cand['M04_current_node_coverage']['candidate_gdn_and_att']['covered_steps']} |",
            f"| M06 terminal slot occupancy ratio | {base['M06_slot_occupancy_ratio']['step_summary']['terminal']:.6f} | {cand['M06_slot_occupancy_ratio']['step_summary']['terminal']:.6f} |",
            f"| M07 terminal resident byte exposure KiB | {base['M07_resident_byte_exposure_KiB']['step_summary']['terminal']} | {cand['M07_resident_byte_exposure_KiB']['step_summary']['terminal']} |",
            f"| M08 raw rehydrate count | {base['M08_raw_rehydrate_count']} | {cand['M08_raw_rehydrate_count']['total']} |",
            f"| M09 rehydrate byte mass KiB | {base['M09_rehydrate_byte_mass_KiB']} | {cand['M09_rehydrate_byte_mass_KiB']['total']} |",
            f"| M10 acquisition incidence | {base['M10_node_touch_acquisition_incidence_mapped']['acquisition_touches']} | {cand['M10_node_touch_acquisition_incidence_mapped']['any_unit_acquisition_touches']} |",
            f"| M11 raw externalize count | {base['M11_raw_externalize_count']} | {cand['M11_raw_externalize_count']['total']} |",
            f"| M12 externalize byte mass KiB | {base['M12_externalize_byte_mass_KiB']} | {cand['M12_externalize_byte_mass_KiB']['total']} |",
            f"| M13 compatible J disclosure | {base['M13_compatible_J_disclosure']:.6f} | {cand['compatible_J_M13']:.6f} |",
            f"| M14 deterministic diff | 0 | {item['deterministic_diff']} |", "",
            "Candidate event split:", "",
            "| metric | GDN | ATT | total |", "|---|---:|---:|---:|",
            f"| M08 rehydrate count | {cand['M08_raw_rehydrate_count']['GDN']} | {cand['M08_raw_rehydrate_count']['ATT']} | {cand['M08_raw_rehydrate_count']['total']} |",
            f"| M09 rehydrate KiB | {cand['M09_rehydrate_byte_mass_KiB']['GDN']} | {cand['M09_rehydrate_byte_mass_KiB']['ATT']} | {cand['M09_rehydrate_byte_mass_KiB']['total']} |",
            f"| M11 externalize count | {cand['M11_raw_externalize_count']['GDN']} | {cand['M11_raw_externalize_count']['ATT']} | {cand['M11_raw_externalize_count']['total']} |",
            f"| M12 externalize KiB | {cand['M12_externalize_byte_mass_KiB']['GDN']} | {cand['M12_externalize_byte_mass_KiB']['ATT']} | {cand['M12_externalize_byte_mass_KiB']['total']} |", "",
            f"Stop-condition violations: {sum(item['stop_conditions'].values())}.", "",
            "Step-aggregate state and occupancy disclosure:", "",
            "| metric | baseline | Candidate A |", "|---|---:|---:|",
            f"| M05 full-node node-steps mean | {base_shape['full_node_node_steps']['mean']:.6f} | {cand_shape['full_node_node_steps']['mean']:.6f} |",
            f"| M05 partial-node node-steps mean | {base_shape['partial_node_node_steps']['mean']:.6f} | {cand_shape['partial_node_node_steps']['mean']:.6f} |",
            f"| M05 empty-node node-steps mean | {base_shape['empty_node_node_steps']['mean']:.6f} | {cand_shape['empty_node_node_steps']['mean']:.6f} |",
            f"| M06 occupancy ratio mean | {base_occ['mean']:.6f} | {cand_occ['mean']:.6f} |",
            f"| M06 occupancy ratio min/max | {base_occ['min']:.6f}/{base_occ['max']:.6f} | {cand_occ['min']:.6f}/{cand_occ['max']:.6f} |",
            f"| M07 byte exposure mean | {base_kib['mean']:.6f} | {cand_kib['mean']:.6f} |",
            f"| M07 byte exposure min/max | {base_kib['min']}/{base_kib['max']} | {cand_kib['min']}/{cand_kib['max']} |", "",
            "Candidate state-shape terminal: "
            f"full={cand_shape['terminal']['full_node']}, "
            f"partial={cand_shape['terminal']['partial_node']}, "
            f"empty={cand_shape['terminal']['empty_node']}. "
            f"State replay binding={cand['terminal_state_replay_matches_runner']}.", "",
        ]
    lines += [
        "## Forbidden interpretations", "",
        "- Raw M08/M11 values are model-internal counts, not comparable effects.",
        "- M09/M12 are identity-mapping accounting disclosures, not measured bandwidth, latency, or economic cost.",
        "- M10 is a mapped descriptor; equality or difference does not establish event equivalence.",
        "- M13 is compatibility disclosure only, not a primary criterion.",
        "- hot and tree remain separate; no pooling, averaging, or generalization.",
        "- Correctness PASS and this accounting do not imply Candidate A is better, worse, production-ready, or causal in a real system.",
    ]
    return "\n".join(lines) + "\n"


def main():
    with open(OFFICIAL_ARTIFACT, encoding="utf-8") as f:
        official = json.load(f)
    traces = R.make_traces()
    runs = {}
    for name, trace in traces.items():
        baseline, states, ok = R.run_baseline(trace)
        candidate_1 = R.CandidateA(trace).run()
        candidate_2 = R.CandidateA(trace).run()
        runs[name] = {
            "baseline_metrics": baseline, "baseline_states": states,
            "baseline_ok": ok, "candidate_1": candidate_1,
            "candidate_2": candidate_2,
        }

    binding = binding_checks(official, runs)
    binding_pass = all([
        binding["runner_sha_matches_official"],
        binding["baseline_blob_matches_official"],
        binding["hot_baseline_matches_official"],
        binding["hot_candidate_counts_match_official"],
        binding["tree_baseline_matches_official"],
        binding["tree_candidate_counts_match_official"],
    ])
    hard_fail = not binding_pass
    binding["all_source_and_artifact_checks_pass"] = binding_pass
    output = {
        "schema": "nodes-out-tier1-mechanism-accounting-v0.1",
        "date": "2026-09-22",
        "status": "MECHANISM_ACCOUNTING_COMPLETE_EFFECT_VERDICT_LOCKED",
        "provenance": {
            "contract_commit": binding["contract_commit"],
            "runner_commit": binding["runner_commit"],
            "baseline_commit": R.BASELINE_COMMIT,
            "baseline_blob": binding["baseline_blob"],
            "runner_sha256": binding["runner_sha256"],
            "official_artifact_sha256": binding["official_artifact_sha256"],
            "extractor_path": EXTRACTOR_REL,
            "extractor_sha256": R.sha256_file(os.path.abspath(__file__)),
            "boundary": "read-only extraction; Runner/baseline/Candidate A unchanged",
        },
        "binding": binding,
        "workloads": {},
    }
    for name, item in runs.items():
        dd = R.deterministic_diff(item["candidate_1"], item["candidate_2"])
        candidate = candidate_metrics(traces[name], item["candidate_1"])
        baseline = baseline_metrics(
            traces[name], item["baseline_states"], item["baseline_metrics"])
        stop = {
            "baseline_regression_fail": not item["baseline_ok"],
            "artifact_or_source_binding_fail": not binding_pass,
            "baseline_current_node_uncovered": (
                baseline["M04_current_node_coverage"]["baseline"]
                ["uncovered_steps"] > 0),
            "candidate_current_node_uncovered": (
                candidate["M04_current_node_coverage"]["candidate_gdn_and_att"]
                ["uncovered_steps"] > 0),
            "candidate_violation": bool(item["candidate_1"].violations),
            "baseline_capacity_exceed": (
                baseline["M06_slot_occupancy_ratio"]
                ["capacity_exceed_steps"] > 0),
            "candidate_capacity_exceed": (
                candidate["M06_slot_occupancy_ratio"]
                ["capacity_exceed_steps"] > 0),
            "candidate_terminal_replay_mismatch": not candidate[
                "terminal_state_replay_matches_runner"],
            "deterministic_diff": dd != 0,
        }
        output["workloads"][name] = {
            "baseline": baseline,
            "candidate": candidate,
            "baseline_regression_ok": item["baseline_ok"],
            "deterministic_diff": dd,
            "candidate_violation_count": len(item["candidate_1"].violations),
            "stop_conditions": stop,
            "steps": len(traces[name]),
        }
        hard_fail |= any(stop.values())
    output["FINAL"] = {
        "mechanism_extraction_complete": not hard_fail,
        "effect_verdict": "LOCKED",
        "tier1_data_collection": "COMPLETE_FOR_THIS_FROZEN_FACE",
    }

    os.makedirs(OUT_DIR, exist_ok=True)
    json_path = os.path.join(OUT_DIR, "tier1_mechanism_accounting.json")
    report_path = os.path.join(OUT_DIR, "TIER1_MECHANISM_ACCOUNTING_20260922.md")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2, sort_keys=True)
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(markdown_report(output))

    print(f"=== Nodes-out Tier-1 mechanism accounting ({OUT_DIR}) ===")
    for name, item in output["workloads"].items():
        base, cand = item["baseline"], item["candidate"]
        print(f"-- {name} --")
        print(f"baseline regression={item['baseline_regression_ok']} "
              f"candidate violations={item['candidate_violation_count']} "
              f"deterministic_diff={item['deterministic_diff']}")
        print(f"M08 rehy baseline={base['M08_raw_rehydrate_count']} "
              f"candidate={cand['M08_raw_rehydrate_count']['total']} "
              f"(no cross-granularity comparison)")
        print(f"M11 ext baseline={base['M11_raw_externalize_count']} "
              f"candidate={cand['M11_raw_externalize_count']['total']} "
              f"(no cross-granularity comparison)")
        print(f"M09 rehy KiB baseline={base['M09_rehydrate_byte_mass_KiB']} "
              f"candidate={cand['M09_rehydrate_byte_mass_KiB']['total']}")
        print(f"M12 ext KiB baseline={base['M12_externalize_byte_mass_KiB']} "
              f"candidate={cand['M12_externalize_byte_mass_KiB']['total']}")
    print(f"binding={binding}")
    print(f"FINAL={output['FINAL']}")
    print(f"artifact={json_path}")
    print(f"report={report_path}")
    return 1 if hard_fail else 0


if __name__ == "__main__":
    raise SystemExit(main())
