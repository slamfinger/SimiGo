# Principle: Official semantics first

> **适用范围说明（2026-11-05）**：该原则源自 2026-09 的 MLX / ChatSession 简化迁移。用于判断是否应复用上游既有语义；不意味着所有后续 backend 都已提供 SimiGo 所需语义，也不排除在证实上游缺口后引入必要的本地实现。

**Status:** Generalized principle  
**Origin:** 2026-09 simplification and ChatSession migration

## Statement

When an upstream runtime already defines the required inference semantics, the application layer should consume that semantic authority rather than recreate a parallel implementation.

## Derivation

1. Identify the required semantic behavior.
2. Locate the upstream API that defines or owns it.
3. Verify the API behavior with source inspection and executable evidence.
4. Keep local code at the integration boundary.
5. Introduce a local abstraction only when a concrete upstream gap is demonstrated.

## Scope

Applies primarily to model/session/generation/cache semantics.

Does not prohibit local code for application concerns such as protocol mapping, process management, lifecycle coordination, or observability.

## Evidence

- `docs/lessons/AUDIT_SIMPLIFY_MIGRATION_LESSONS_2026-09-12.md`
- `docs/audit/POST_AUDIT_DELETION_RECORD_2026-09-11.md`
- `docs/history/CORE_ARCHITECTURE_BASELINE_V5_20260912.md`（原 `README_base.md`）, §5 and §13

## Related architecture

v5.0 Core Architecture Baseline.
