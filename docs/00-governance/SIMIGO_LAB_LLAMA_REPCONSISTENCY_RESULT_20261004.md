# SimiGo-Lab LLAMA Representation Consistency Replication Result

Date: 2026-10-04  
Status: `EXECUTED / RAW EVIDENCE SEALED / CROSS-BACKEND REPLICATION PASS / LLAMA-SLICE BOUNDED`  
Harness code commit: `716ff1d3e37af93a4fce413e1b2d5d1d1c72e73b`  
Evidence directory: `docs/02-evidence/llama-representation-consistency-20261004/`

## Scope

This is the minimal llama-server replication of the MLX Representation
Consistency Boundary result. It does **not** reopen Gδ, add C1/C3, test KV
cache, test Oversized, or propose an integrity mechanism.

Question executed:

```text
same Execution ID
same logical position
same representation position
same token-prefix length
different prefix content
    ↓
backend binding accepted?
    ↓
real llama-server execution?
    ↓
observable output divergence?
```

## Command

See `RUN_COMMAND.txt`.

Server:

```text
llama.cpp server 0.5.0-dev build 11284 commit 25747b08
model = Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
endpoint = http://127.0.0.1:18080
ctx-size = 8192
parallel = 1
```

## Fixed controls

```text
execution ID           = llama-repconsistency-single
logical position       = 0
representation position = 0
seed text              = The project directory ReferenceFiles contains
                         project management documents.
next input             = What folder did I create?
prediction tokens      = 12
temperature            = 0
seed                   = 42
prefix length          = 10 tokens
only content delta     = token index 8: 9017 -> 9018
```

## Raw observation

```text
C0:
  backendBindingAccepted = true
  realLlamaExecution     = true
  generatedTokenIDs      = [198,760,2313,6025,16699,10492,5435,2313,6044,9017,13,198]
  generatedText          = "\nThe project directory ReferenceFiles contains project management documents.\n"

C2.rep1:
  backendBindingAccepted = true
  realLlamaExecution     = true
  generatedTokenIDs      = [198,760,2313,6025,16699,10492,5435,2313,6044,9018,13,198]
  generatedText          = "\nThe project directory ReferenceFiles contains project management century.\n"
  difference             = DIFFERENT_FROM_C0(token_ids)

C2.rep2:
  identical token IDs and text to C2.rep1
  difference             = DIFFERENT_FROM_C0(token_ids)

C2.rep3:
  identical token IDs and text to C2.rep1
  difference             = DIFFERENT_FROM_C0(token_ids)
```

Prefix evidence:

```text
original:
  tokens = [760,2313,6025,16699,10492,5435,2313,6044,9017,13]
  token_count = 10
  token-array sha256 = sha256:c681aa9d1eaed1265bdc9baf5ef8f94eae2ce2401b375cf85b1b424da4a18304

mutated:
  tokens = [760,2313,6025,16699,10492,5435,2313,6044,9018,13]
  token_count = 10
  token-array sha256 = sha256:e2d421191f15bafb2bb47b1a84e7333d091f36a19821945c5cf2af19b864be1d
```

## Reading

```text
C2.rep1 = C2.rep2 = C2.rep3
C2.rep1/2/3 != C0
c2StableOutputDifference = true
```

Only bounded claim:

> In the current llama-server full-prefix slice, same-ID / same-position /
> same-length / different-token-content is accepted by the existing Execution
> State backend binding, reaches real llama-server execution, and stably
> produces observable output divergence from C0.

## Relationship to MLX result

This is a cross-backend replication of the observed structure:

```text
same identity + same position + same length + different content
    → accepted
    → real backend execution
    → stable observable divergence
```

It does not prove that both implementations share an integrity mechanism, nor
that all representations behave this way.

## Not established

```text
Not established: KV-cache representations.
Not established: MLX + llama semantic equivalence.
Not established: correctness or quality of either output.
Not established: representation integrity theory.
Not established: contract completeness or mathematical minimality.
Not established: behavior under concurrency, sampling, persistence,
  restore-from-disk, or production chat pipeline.
```

## Potential future design question

Whether content integrity should become a detectable Execution State boundary
remains deferred. This result does not authorize hash, anchor, provenance, or a
new consistency gate.
