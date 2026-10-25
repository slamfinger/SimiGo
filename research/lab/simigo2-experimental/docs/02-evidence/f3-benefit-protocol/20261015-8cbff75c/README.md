# F3 benefit protocol — first controlled run — 20261015

## Verdict: BENEFIT NOT ESTABLISHED (honest negative result)

Three paired canonical cold vs adopted-warm legs under one model load
(Qwen3-Coder-30B-A3B-4bit; ~650-token prompt; stride 256; boundary 512;
16 tokens; swap stable at 1.70 GiB across the timed region):

- Wall time (the capability metric): cold 281/288/290 s vs warm
  669/681/671 s — the adopted path is consistently ~2.3x SLOWER than the
  cold path. Reproducible within 1% per side; not noise.
- Fork-reported prompt metric: cold 0.9 s vs warm 0.3 s — determined to be
  asyncEval graph-SUBMISSION time, not prefill compute (650 tokens of a
  30B cannot prefill in 0.9 s on this machine). Renamed
  `promptSubmissionSeconds` in the harness; it must never decide the
  verdict alone.

Conclusions:
1. Hook-hit evidence says nothing about benefit; the first CONTROLLED
   measurement shows the adoption path currently COSTS wall time on this
   model/machine. Candidate causes for the next unit: per-step attention
   over restored (possibly dequantized) KV rows, artifact array
   materialization, interaction with Memory.clearCache between legs.
2. The protocol itself worked: pairing controlled the variance that made
   earlier single-run timing meaningless (per-side spread < 1%).
3. `pass` now requires WALL median savings + submission savings + stable
   swap; this run's data would fail that criterion and is recorded as
   such (the run predates the corrected field names; interpretation here
   is authoritative).
