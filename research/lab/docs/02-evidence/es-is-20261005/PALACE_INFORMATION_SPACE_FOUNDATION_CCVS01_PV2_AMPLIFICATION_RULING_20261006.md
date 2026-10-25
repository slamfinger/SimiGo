# CCVS-01 PV2 — Human Ruling on PB-B10 / PB-B11 & Calibration Commission

Date: 2026-10-06  
Type: `HUMAN RULING / L2 AUTHORITATIVE`  
Ruling: `B10 = UNCALIBRATED / PROTOCOL-VALIDITY-FLAGGED (3x bound unchanged); B11 = NOT-COMPARABLE; commission narrow Amplification Measurement Calibration Study`

## Ruling content

```text
PB-B1..B9    = ACTIVE
PB-B10       = UNCALIBRATED / PROTOCOL-VALIDITY-FLAGGED
PB-B11       = NOT-COMPARABLE
Protocol     = FROZEN; bound values unchanged; no re-tuning
P8 crash/recovery = may continue
Candidate manifest / adapter / conformance = may be prepared
Candidate controlled performance comparison = PAUSED until amplification
               measurement semantics are sealed; amplification results must
               not enter candidate-level Pareto judgment until the primary
               measurement is ACTIVE
```

Core reasoning: the measured 6.31x proves this workload exceeds 3x under the
current implementation and measurement; it does not prove 3x is unreasonable.
The first task is not changing the bound but verifying whether the current
measurement observes R5's "physical durable footprint" (durable bytes at rest)
or device writeback traffic. These are different physical quantities and must
not share one metric name. Raising 3x to 7x/8x to make Baseline A pass is
explicitly forbidden.

## Calibration study mandate (narrow scope)

```text
C1  Verify R5's physical-durable-footprint definition is reliably observable
    on this host.
C2  Explicitly separate three physical quantities:
      steady-state footprint (durable bytes at rest),
      peak footprint (maximum at-rest footprint during the run),
      write traffic / write amplification (bytes pushed toward the device).
C3  Re-measure B10/B11 on Baseline A with the calibrated primary metric.
```

Must itemize how each component counts:

```text
logical payload; entity representation bytes; registry SQLite file; WAL;
FTS/index; temporary artifacts; duplicate representations; allocated blocks.
```

Device writeback counters are diagnostic ("how much reached the medium"),
never the primary amplification ("how much durable physical footprint the
Information Space occupies"). No estimation; no substitution of a
"reasonable-looking" number; Baseline A missing a bound is a valid research
finding, not a failure to hide.

Evidence note: PV2 behaved exactly as designed — ACTIVE / UNCALIBRATED /
NOT-COMPARABLE surfaced a measurement-definition gap instead of swallowing an
anomalous number.
