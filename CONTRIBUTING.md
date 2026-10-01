# Contributing to SimiGo-Lab

Contributions may include conformance cases, representation declarations,
backend adapter evidence, runtime fixes, experiment reproducibility, and
documentation corrections.

## Contract discipline

Do not silently reinterpret the frozen Execution State Contract. Semantic
membership, invariant meaning, and lifecycle obligations change only through a
separate Closure Revision Gate with explicit human review.

## Licensing and hygiene

- Code and executable material: Apache-2.0.
- Documentation, specifications, and evidence records: CC-BY-4.0.
- Do not commit model weights, local user paths, signing team IDs, device
  serials, build artifacts, or private transcripts.

Run:

```bash
tools/open_source_audit.sh
(cd simigo2-experimental && swift test)
```
