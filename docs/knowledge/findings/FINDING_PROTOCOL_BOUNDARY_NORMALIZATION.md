# Finding: Protocol boundary normalization is required for tool-call continuity

**Status:** Evidence-backed finding  
**Date:** 2026-09-22  
**Evidence window:** 2026-09-12

## Finding

When an external wire protocol represents a tool-call field differently from the upstream model/session representation, normalization must occur at the protocol boundary before the message is reintroduced into the conversation state.

For SimiGo, OpenAI-compatible `function.arguments` may arrive as a JSON string while the official tool-call representation expects structured JSON. Failing to normalize the two representations can silently remove tool-call state and break subsequent session continuity / KV reuse.

## Evidence

`docs/lessons/AUDIT_SIMPLIFY_MIGRATION_LESSONS_2026-09-12.md` records a reproduced failure:

- tool round followed by `reuse=false`;
- `prefixMismatch` identified a tool-state discrepancy;
- the string/object representation mismatch caused Codable decoding to collapse the tool payload;
- boundary normalization restored the semantic representation.

## Boundary

The finding is about representation compatibility at an integration boundary. It does not justify a new parallel tool protocol or raw-output parser.

## Traceability

- Lesson: `docs/lessons/AUDIT_SIMPLIFY_MIGRATION_LESSONS_2026-09-12.md`, §1
- Architecture: `README_base.md`, §5.2
