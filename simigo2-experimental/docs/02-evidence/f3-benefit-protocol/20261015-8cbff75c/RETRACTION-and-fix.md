# Retraction: the "benefit not established" verdict was a measurement bug

The first controlled run (f3-run1) reported warm ~2.3x SLOWER than cold
(669-681 s vs 281-290 s). Those numbers were impossible on their face: the
process completed in ~11 minutes while the legs summed to ~48 minutes of
claimed wall time, and the instrumented follow-up (f3-run2) recorded a
first-chunk latency LARGER than the leg's own wall time — a monotonicity
violation.

Root cause: Duration→seconds conversion divided attoseconds by 1e15 instead
of 1e18, inflating every fractional second by 1000x. A 10-line reproduction
confirms (Duration 284.15 s computed as 434.0). The same conversion existed
in the engine's per-token latency stat. All four seconds-intent sites fixed
(millisecond sites were already correct); suite 367/3/0.

Corrected measurement (f3-run3, same protocol: one load, paired canonical
legs, 3 pairs, boundary 512, 16 tokens):

- cold wall 1.28/1.30/1.28 s vs warm 0.67/0.68/0.66 s — paired savings
  ~0.62 s (48%), per-side spread < 2%
- TTFT 0.88 s → 0.29 s (3x) — the direct prefill-savings signature
- hook: 1 hit @ 512 per warm leg, 0 in cold legs; swap stable
- pass = True under the corrected criterion (wall median savings +
  submission savings + stable swap)

F3 verdict with corrected instruments: ACTUAL BENEFIT ESTABLISHED for the
canonical small-scale path on this model. The earlier negative is retracted;
the attribution unit's outcome is "measurement defect found by the protocol's
own consistency checks, fixed, positive benefit measured". The protocol
design (pairing, internal consistency fields) is what caught the bug —
single-run timing would not have.
