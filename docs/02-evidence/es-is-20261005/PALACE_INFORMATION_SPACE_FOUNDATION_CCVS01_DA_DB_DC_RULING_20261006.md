# CCVS-01 — Human Ruling D-A / D-B / D-C (Amplification Closure)

Date: 2026-10-06  
Type: `HUMAN RULING / L2 AUTHORITATIVE`  
Ruling: `D-A ACCEPT; D-B ACCEPT; D-C ACCEPT`

## Frozen outcomes

```text
Q1 steady-state allocated-block footprint (entities + registry DB + WAL + SHM
   + steady-state temp) = PRIMARY metric for PB-B10/B11.
Q2 peak footprint = recorded metric. Q3 device-writeback traffic = diagnostic
   only, never amplification.
PB-B1..B9 = ACTIVE / MET
PB-B10    = ACTIVE / MET   (Q1 = 1.11x; 3x bound unchanged; the earlier 6.31x
           was Q3 mislabeled as amplification — a measurement invalidity
           correction, not bound tuning)
PB-B11    = NOT-YET-VALIDATED; candidate-class vocabulary has no such state,
           so the standing class remains NOT-COMPARABLE with registered reason
           "fixture non-conformance / superseded measurement"; a fresh
           compliant run overrides it. Old numbers must not enter candidate
           comparison.
CCVS-01-PB v1.2 = FROZEN (unchanged by all of the above)
```

## D-B fixture semantics (accepted)

```text
Large-file fixture = seed-derived deterministic valid UTF-8 text;
master seed fixed; generator algorithm fixed; generator version + content
hash recorded; same seed + version reproduces identical fixtures; size band
per PB-F2 (10 MiB). No protocol-external special binary; target = determinism
+ valid UTF-8 + PB-F2 sizes + low compressibility bias.
```

## D-C defect fix (accepted)

Zero-filled large fixtures in the driver = implementation/fixture-generation
non-conformance to PB-F2 (protocol already required deterministic UTF-8
text-bounded fixtures). Fixed pre-run; no Phase B re-freeze required. The
chain zero-fill → APFS compression → anomalously low allocated blocks is NOT
a real B11 workload result.

## Reporting language (mandatory)

B11 results must be stated as: "Q1 steady-state durable allocated-footprint
amplification under the specified filesystem/fixture conditions = X" — never
as bare "physical amplification". Filesystem compression / sparse allocation /
logical size / physical allocation remain distinct concepts; filesystem
compression itself may become a separate diagnostic dimension by future
ruling.

## Execution state

```text
P8 crash/recovery (F1–F9 → G2)        = AUTHORIZED
Candidate manifest/adapter/conformance = AUTHORIZED
Candidate performance comparison       = HOLD until B11 compliant re-run
                                         closes
```

Closing note: this calibration turned "amplification" from a concept that
could be impersonated by write-traffic into an observable, reproducible,
comparable physical-footprint metric.
