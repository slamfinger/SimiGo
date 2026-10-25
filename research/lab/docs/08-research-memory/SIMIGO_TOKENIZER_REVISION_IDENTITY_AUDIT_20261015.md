# Tokenizer Revision Identity Audit

- Audit ID: `AUDIT-TOKENIZER-REVISION-IDENTITY-20261015` (rev 3, review-final)
- Type: `STATIC REVIEW + READ-ONLY DIAGNOSTIC / NO PRODUCTION CHANGES / NO EXPERIMENTS`
- Baseline: `main = c81e6e53`
- Evidence provenance: the two-model observations are submitter-run local
  diagnostics (env-gated, asserted), not independently reproduced by the
  reviewer; code-level findings are line-verified on both sides.
- Scope: the revision fence's tokenizer-class semantics (filtering, path
  normalization, symlink resolution, ordering, serialization) and
  `EngineModelIdentity`'s tokenizer digest; interaction with the ctime
  reinforcement (PR #5–#8, closed — NOT reopened by this audit).

## Current behavior (code-cited)

`EngineModelIdentity.compute` (EngineSessionBaseline.swift):

1. Entry guard: `values?.isRegularFile == true` on the ENUMERATOR URL —
   attributes of the link itself on symlink layouts.
2. Weights: per-file `rel:size:contentDigest` lines, **sorted**, digested —
   per-file encoding present.
3. Tokenizer-like (name prefix set, ≤8 MiB): raw bytes **appended into one
   buffer in enumeration order**, no per-file path/size/boundary encoding,
   no sorting, then `digest(of: [String(decoding: tokenizerData, as: UTF8.self)])`.

`modelDirectoryRevision` (MLXPrefixCrossSessionCache.swift, post PR #5/#8):
resolves each candidate through `resolvingSymlinksInPath()`, fingerprints
target name/size/crtime/mtime/ctime per file, **sorted** entries, `\t`/`\n`
serialization. Candidate set intentionally mirrors identity's (same prefixes,
same 8 MiB cap).

## PROVEN findings (read-only diagnostic, 2026-10-15)

`TokenizerIdentityAuditDiagnostics` (skip-if-absent) on the two real local
HF snapshots (30B `6e302ea6…`, 35B `31a01064…`):

- `isRegularFile` of a raw snapshot entry = **false** (link, not target;
  the diagnostic also asserts the entry IS a symlink and its RESOLVED
  target IS a regular file, proving the HF-link scenario is what is
  measured).
- On the two OBSERVED snapshots, all four digests (weights and tokenizer,
  both models) = `e3b0c44298fc…` — the SHA-256 of EMPTY input;
  `weights-differ=false`, `tokenizer-differ=false`; repeated computation
  stable (trivially). By code derivation the same empty-input result
  follows for ANY layout in which every candidate is skipped by the
  `isRegularFile` guard — the standard HF snapshot symlink layout being
  the known instance. A statement about the guard's behavior on such
  layouts, NOT a verification against every HF-resident model.

Consequences, honestly bounded:

- **The content-digest COMPONENT of host namespaces loses all discriminating
  power on the HF layout** (conditional, tightened per review): the digest
  is constant, but the full namespace still carries `modelID` = snapshot
  directory basename, which DOES separate different snapshots. Residual
  protection therefore rests on (a) that `modelID` component, (b) the
  caller-directory context-hook refusal (FCI line), and (c) the drift
  fence — all functioning. What does NOT operate behind symlinks is the
  same-name-different-content discrimination the digest was built for.
- **Engine baseline identity VALIDATION cannot discriminate on HF
  (conditional, tightened per review)**: DCC-1 recovery compares the
  weights/tokenizer identity FIELDS, and when both collapse to the empty
  constant those field comparisons cannot distinguish models. However,
  distinct STANDARDIZED directory paths derive distinct DEFAULT baseline
  storage roots (keyed by the path's SHA-256 in
  OversizedEnginePersistence.directories), so different paths do not share
  a baseline through the default layout. The concrete exposure is a same-path
  content swap, or any host that shares a baseline root across models —
  not automatic cross-model baseline reads. Validation-coverage finding;
  no frozen Tier-1 semantics are touched or changed by this audit.
- For the two observed HF snapshots, the fence resolves symlinks and
  fingerprints the METADATA of its declared candidate set, while
  `EngineModelIdentity` skips those linked candidates under the current
  guard. This demonstrates inconsistent coverage for the audited layout;
  it does not establish that every HF model has the same layout, nor that
  the fence covers all model-related files or proves file contents.

## PROVEN by code reading (plain, non-symlink directories)

- Tokenizer accumulation is **enumeration-order dependent** (unsorted) —
  identity for a multi-file tokenizer set can flip with directory iteration
  order (spurious namespace change → unnecessary cold miss).
- No per-file encoding → **partition ambiguity**: `{tokenizer.json:"AB",
  vocab.txt:"C"}` and `{tokenizer.json:"A", vocab.txt:"BC"}` produce the
  same digest.
- `String(decoding:as:UTF8.self)` is a **lossy decode** (invalid bytes →
  U+FFFD) before hashing — distinct byte streams can collide after
  replacement normalization.

## CONSTRUCTIBLE but UNPROVEN

- Fence serialization ambiguity: file/blob names containing `\t` or `\n`
  can forge entry boundaries (Finder permits such names). Practical risk
  low; fix is length-prefixing if ever needed.
- `added_tokens.json`, `config.json`, generation configs affect loading
  behavior but are in NEITHER set — declared residual (do not silently
  widen either set).

## Interaction with the ctime reinforcement

Orthogonal layers, UNEQUALLY effective on the audited layout: the
ctime/fence protects within-activation for its candidate set; content
identity does not function where its guard skips linked candidates. The
audit question "independent or interacting?" is answered: mechanically
independent, operationally complementary — on the audited snapshots the
identity's collapse left the fence as the working change signal for the
fence's declared candidates.

## Diagnostic contract (per review)

`TokenizerIdentityAuditDiagnostics` is env-gated
(`SIMIGO_TOKENIZER_IDENTITY_AUDIT_DIRS`, two colon-separated snapshot
paths) and asserts rather than prints: it probes a selected `.safetensors`
entry for the raw-link `isRegularFile == false`, and asserts the CURRENT
defect (both models' digests equal the empty-input constant) — the
assertion is intentionally inverted-flippable: V1 must turn it into a
discrimination assertion. The gate keeps future fixed identities from
scanning multi-GB models in regular test runs.

## Minimal verification proposals (future, separately authorized)

- V1: resolve symlinks inside `EngineModelIdentity` (mirror the fence);
  verify 30B/35B digests then differ, and repeated computation is stable.
- V2: per-file `path:size:digest` sorted lines for tokenizer inputs (kills
  order dependence and partition ambiguity); regression with shuffled
  enumeration and split-content counterexamples.
- V3: hash tokenizer bytes as `Data`, not lossy-decoded `String`.
- V4: engine-baseline cross-model probe asserting a mismatch once V1 lands.

## Non-goals

No production change in this audit; no widening of identity inputs; no
frozen-contract or DCC-1 Tier-1 modification; PR #5–#8 conclusions stand.
