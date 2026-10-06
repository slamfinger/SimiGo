# CCVS-01 PV1 — Baseline A (A1) Controlled Run Record

Date: 2026-10-06  
Status: `SMALL COMPLETE (5/5 VALID) / MEDIUM RUNNING`  
Frozen protocol: `CCVS-01-PB v1.2`  
Data roots (outside Lab, PB-F4): `/Users/mr.simi/Documents/CCVS01-Bench/{SMALL,MEDIUM}`  
Master seed: `20261006` (PB-F2)  
Admission: resource gate PASS (free disk >= 3x declared); quiescence = three
consecutive 5 s windows < 20% non-benchmark CPU (one violation recorded and
re-checked: windows [0.117, 0.203, 0.116] → RESOURCE_GATE_BLOCKED → retry PASS).
Environment manifest: recorded per tier in `environment.json`.

## SMALL ×5 — all VALID

```text
integrity final = clean on all runs
invariant notes = none on all runs
mode = cold, serial, median-of-valid-runs aggregation
```

Headline (median-of-runs, WL6 segment where defined):

| Operation | P50 | P95 | P99 |
|---|---:|---:|---:|
| create | 7.70 ms | 19.54 ms | 37.4 ms |
| lookup | 0.21 ms | 0.34 ms | 0.54 ms |
| move | 0.11 ms | 0.23 ms | 2.33 ms |
| session append | 0.09 ms | 0.16 ms | 0.35 ms |
| relation insert | 0.08 ms | 0.14 ms | 0.22 ms |
| 2-hop traversal | 0.04 ms | 0.06 ms | 0.08 ms |
| search query | 0.07 ms | 0.12 ms | 0.15 ms |
| revise | 7.9 ms | 19.4 ms | 26.5 ms |
| pin read | 0.011 ms | 0.021 ms | 0.029 ms |
| startup/open | 4.2 ms | — | — |
| index rebuild | 52 ms | — | — |
| integrity check | 0.47 s | — | — |

## PV2 bound classification — provisional (SMALL only; final on MEDIUM)

```text
PB-B1..B9 latency bounds: met on SMALL (informational; binding = MEDIUM WL6).
PB-B10 wl1 ingest amplification = 6.0x measured with exact logical payload
       bytes (33.2 MB logical, ~197 MB device) > 3x bound → per PV2, since
       Baseline A itself misses, classify UNCALIBRATED → this bound becomes
       PROTOCOL-VALIDITY-FLAGGED and requires a Human ruling. No candidate
       may be eliminated by it. Mechanism hypothesis: temp-write + rename
       entity durability doubles device writes, plus per-transaction WAL/FTS
       cost at synchronous=FULL — to be examined in the ruling, not by
       changing the protocol mid-run.
PB-B11 large-file amplification = 0.12x < 1x → instrumentation anomaly
       (windowed device-writeback accounting does not capture the writes);
       recorded NOT-COMPARABLE for this methodology per frozen §4.1
       (never approximated). Requires a Human methodology ruling.
```

## Bring-up defects registered as evidence

See `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_A1_BRINGUP_DEFECTS_20261006.md`
(D1 double-finalize lifecycle defect; D2 latestRevision deterministic ordering
defect — semantic ordering authority = deterministic insertion order).

## Benchmark driver notes (instrumentation, not protocol)

```text
proc_pid_rusage on macOS 26+ writes the rusage struct directly into a
caller-allocated buffer (out-pointer ABI from older docs produced SIGSEGV);
driver allocates rusage_info_v2-sized buffer. Verified separately: a 100 MB
write produced an exact 104857600-byte counter delta.
Raw artifacts: result.json per run, aggregate.json (median-of-runs),
environment.json per tier under the data roots.
```
