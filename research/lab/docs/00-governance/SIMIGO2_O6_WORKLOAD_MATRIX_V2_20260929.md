# SimiGo-Lab — O6 Execution State Workload Matrix V2/V3 — PASS — 2026-09-29

Status: **O6_EXECSTATE_WORKLOAD_MATRIX_V2_PASS / W0-W8 PASS / W9 NOT CLAIMED**
Protocol: `G1.9-O6.EXECSTATE.V2`
Model: Qwen3-Coder-Next-4bit, 48 layers, `segment-size=8` (6 segments)
Command: `simigo2ctl o6-execstate MODEL --tokens 4 --segment-size 8`

## Result

```text
status                     PASS
overallPass                true
segment size / count       8 / 6
peak footprint             8,041 MiB <= 30,720 MiB
max swap                   0 MiB
segment transitions        292
wall time                  467.6 s (diagnostic harness; not performance evidence)
```

## Workload coverage

| Workload | Evidence in V2 | Result |
| --- | --- | --- |
| W0 linear generation | parent bootstrap and later parent continuation | PASS |
| W1 capture | checkpoint binding / representation capture before fork and restore | PASS |
| W2 fork | child C plus repeated children R1/R2/L derived from P | PASS |
| W3 branch divergence | child continuation differs from parent reference | PASS |
| W4 restore | C restored to fork point; L restored after two continuations | PASS |
| W5 branch release | current child representations released before replay | PASS |
| W6 repeated fork/restore | two additional forks restored/replayed from same checkpoint | PASS |
| W7 long-running branch | branch advanced through two continuations, then restored | PASS |
| W8 memory pressure gate | explicit oversized release, zero swap, deterministic recovery | PASS |
| W9 cancellation | **not implemented / not claimed** | N/A |

## Checks

```text
PARENT_IDENTITY_STABLE                              PASS
CHILD_LINEAGE_TRACEABLE                             PASS
FORK_DIVERGENCE                                     PASS
RESTORE_TO_FORK_POINT                               PASS
CHILD_DETERMINISM_THROUGH_SEGMENT_EVICT_RESTORE     PASS
PARENT_NON_INTERFERENCE                             PASS
W6_REPEATED_FORK_RESTORE                            PASS
W7_LONG_RUNNING_BRANCH_RESTORE                      PASS
W8_MEMORY_PRESSURE_RELEASE_RECOVERY                 PASS
RESIDENCY_BOUNDED_ZERO_SWAP                         PASS
SEGMENT_TRANSITIONS_EXECUTED                        PASS
```

W6 detail: R1/R2 are distinct logical branches derived from P's same
checkpoint. Each ran its branch, released its current representation,
restored to position 1, and replayed C's continuation; both replays matched
C's greedy token IDs.

W7/W8 detail: branch L advanced through two continuations to position 3.
Its current representation was then released (the oversized segment-weight
release), L was restored to position 1, and replay matched C's continuation.
At the explicit pressure gate the footprint was 7,612 MiB and swap was
0 MiB. This is the harness's declared release/recovery pressure action, not
an OS memory-pressure injection.

## Boundary

```text
EXECUTION_STATE_X_OVERSIZED
W0-W8_SEGMENT_EVICT_RESTORE_MATRIX
W9_CANCELLATION_NOT_CLAIMED
HARNESS_LEVEL
NOT_A_PERFORMANCE_CLAIM
NOT_A_UNIVERSAL_ARCHITECTURE_CLAIM
```

The cacheless greedy executor re-materializes segments on demand and owns no
KV authority. W9 remains a separate gate because cooperative cancellation is
not plumbed through `O6SegmentedCore.greedy`.

Artifact:
`simigo2-experimental/results/o6-workload-matrix/qwen3-coder-next-4bit-v2.json`.

## V3 update — W9 cooperative cancellation

V3 adds `O6GenerationCancellationToken` and checks cancellation at a complete
greedy-token boundary. A segment is never split. In the real oversized run,
branch X was cancelled after one complete token; the pre-cancel binding stayed
at checkpoint position 1, the consumed prefix reconstructed the expected
one-token advanced payload, logical restore returned X to position 1, and a
full replay matched C's token IDs.

V3 result:

```text
status                     PASS
overallPass                true
checks                     12/12 PASS
peak footprint             8,032 MiB <= 30,720 MiB
max swap                   0 MiB
segment transitions        322
wall time                  569.8 s (diagnostic harness; not performance evidence)
```

Two earlier V3 attempts failed because the gate compared the cancelled state
to the full four-token payload rather than the exact cancelled-token prefix.
Both failed artifacts are retained as harness-assertion history; cancellation
itself returned one token in each attempt. The corrected V3 artifact is
`qwen3-coder-next-4bit-v3.json`.
