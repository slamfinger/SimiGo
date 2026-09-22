# Invariant: Logical identity and physical compute state remain separate

**Status:** Core invariant  
**Current baseline:** v5.0 Core Architecture Baseline

## Statement

Logical Context State, Execution State, Physical KV State, Resource State, and Protocol/Stream State must not assume one another's ownership.

In particular:

- Session / Branch / Request identify logical work;
- Execution controls computation;
- Physical KV represents completed computation;
- Resource state governs physical residency;
- Protocol state represents the external interface.

Physical reuse may cross logical contexts when semantic compatibility and token-prefix conditions are satisfied.

## Why it holds

Conflating these states makes protocol identifiers, session identity, execution scheduling, or resource residency incorrectly determine physical reuse or lifecycle semantics.

The v5.0 architecture explicitly separates these domains and defines Physical KV as a compute result rather than conversation memory.

## Evidence

- `README_base.md`, §2–§6 and §11
- `docs/decisions/V4_5_STABLE_FOUNDATION_BASELINE.md`
- `docs/lessons/AUDIT_SIMPLIFY_MIGRATION_LESSONS_2026-09-12.md`, §2

## Consequence if violated

A local implementation can accidentally make session continuity, request IDs, or protocol objects authoritative over physical cache reuse, producing false reuse or unnecessary rebuilds.

## Validation

Future changes touching Session, KV, Scheduler, Resource, or Protocol boundaries must preserve this separation and include evidence for any claimed change in ownership.
