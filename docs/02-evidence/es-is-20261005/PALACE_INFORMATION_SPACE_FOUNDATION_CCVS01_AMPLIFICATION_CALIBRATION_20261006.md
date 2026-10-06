# CCVS-01 Amplification Measurement Calibration Study — Results

Date: 2026-10-06  
Status: `DELIVERED / AWAITING HUMAN RULING`  
Mandate: `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_PV2_AMPLIFICATION_RULING_20261006.md`  
Method: `CarrierSQLiteCalibration` (fresh isolated root, exact logical accounting, allocated-blocks footprint, device-writeback as diagnostic)

## C2 — three physical quantities, now separated

```text
Q1 steady-state footprint (PRIMARY for B10/B11)
   = allocated blocks (stat st_blocks) of durable artifacts at rest:
     entity files + registry.sqlite + -wal + -shm + temp leftovers.
   Definition-faithful to R5 "physical durable footprint".
Q2 peak footprint = max Q1 sample during the run (sampled, not primary).
Q3 write traffic / write amplification (DIAGNOSTIC ONLY)
   = per-process device-writeback delta. Measures what reached the medium,
     not what the Information Space occupies. NOT the same metric as Q1;
     must never be reported as amplification.
```

## C1 — observability verdict

Q1 is reliably observable on this host (allocated-blocks walk verified
per-file). Q3 verified exact for a controlled 100 MB write (delta =
104857600) but is asynchronous/device-coupled and must stay diagnostic.

## Baseline A re-measurements

Small-shape ingest (1000 objects, exact logical payload 33,434,538 B):

```text
entity allocated          = 35,340,288   (1.057x)
registry DB allocated     =    790,528
WAL at rest (open)        =  1,052,672   (after clean close/checkpoint = 0)
SHM                       =     32,768
Q1 steady-state footprint = 37,216,256   → amp = 1.11x (open) / 1.08x (closed)
Q3 write traffic          = 192,843,776  → 5.77x (diagnostic)
```

Interpretation: the earlier PB-B10 = 6.31x was measuring Q3 (write traffic),
not R5's Q1 footprint. Under Q1, Baseline A wl1 amplification = 1.11x,
within the frozen 3x bound.

## C3 — B11 large-file case: two findings

```text
F1  Device-writeback counters are asynchronous — unusable for B11 (confirmed;
    matches the NOT-COMPARABLE ruling).
F2  APFS transparent compression: zero-filled and highly repetitive fixtures
    allocate far fewer blocks than their logical size (10 x 10 MiB zero or
    repetitive-text fixtures → ~10.5 MB allocated). Footprint measurements
    therefore depend on fixture compressibility. The benchmark driver's
    zero-filled large fixture also deviates from PB-F2 (deterministic UTF-8
    text). High-entropy UTF-8 fixtures are PB-F2-compatible and compress
    poorly; adopting them is a fixture-protocol question reserved for Human
    ruling, since PB-F2 is frozen.
```

## Pending Human decisions (after this study)

```text
D-A  Adopt Q1 (allocated-blocks steady-state footprint) as the primary
     PB-B10/B11 metric, with Q3 retained as labeled diagnostic. Then re-measure
     B10 = 1.11x (ACTIVE, met).
D-B  B11: re-run with PB-F2-compatible high-entropy UTF-8 fixtures (requires
     confirming that seeded random UTF-8 satisfies PB-F2 determinism), or keep
     B11 NOT-COMPARABLE for this phase.
D-C  Whether driver large-file fixtures must be corrected from zero-fill to
     UTF-8 text as a fixture-generation defect fix (pre-run fix, like D1/D2).
```

No protocol value was re-tuned. Baseline A missing a bound remains a valid
research finding; PV2 surfaced the measurement-definition gap exactly as
designed.
