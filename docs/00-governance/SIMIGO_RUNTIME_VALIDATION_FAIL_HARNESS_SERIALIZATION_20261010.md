# Runtime validation result — harness serialization failure

> **Status:** RUNTIME VALIDATION FAIL — ONE-RUN STOP RULE ENFORCED
> **Date:** 2026-10-10

## 1. Execution fact

The authorized isolated validation harness was compiled and invoked once.
The adapter validation loop completed its in-memory execution path, but the
harness then threw an `NSInvalidArgumentException` while serializing evidence:

```text
Invalid type in JSON write (__SwiftNull)
```

The exception occurred before `validation-evidence` was created. Therefore no
case-level evidence, lifecycle evidence, representation evidence, checksum
list, or terminal evidence file was materialized.

## 2. Terminal classification

The required evidence is missing. Under the authorization, missing required
evidence is `RUNTIME_VALIDATION_FAIL`. This is not a claim that any semantic
case decision failed; the in-memory case outcomes were not captured and cannot
be reconstructed.

```text
authorized runs = 1;
executed runs = 1;
terminal state = RUNTIME_VALIDATION_FAIL;
evidence state = MISSING / HARNESS SERIALIZATION FAILURE;
repair = FORBIDDEN;
rerun = FORBIDDEN;
second execution request = FORBIDDEN;
case expansion = FORBIDDEN.
```

## 3. Binding

```text
Runtime Validation Manifest SHA256 =
  0b7a6a0c66fea6c6be2c608c2f6cf8d0fe0275a293d45ad69d1af1e35d8035c3;
Adapter SHA256 =
  87e28403cece2be47243b0ba523c687d1fed6425d08cfab215ed1378ca89d3ec;
harness source path =
  simigo2-experimental/Tests/SimiGo2ExperimentalTests/IntegratedESPalaceAuthorizedRuntimeValidation.swift;
evidence root =
  integrated-es-palace/runtime-adapter-v1/validation-evidence.
```

## 4. Post-run state

The uncommitted post-run harness edit was reverted. The authorized manifest
and adapter source remain bound to their pre-run hashes. No runtime validation
may be invoked again without violating the one-run stop rule.

```text
production deployment = NOT AUTHORIZED / NOT PERFORMED;
canonical PALACE mutation = false;
canonical Information Space mutation = false;
D-002 rerun / repair = false;
Integrated SimiGo full production proof = NOT ESTABLISHED;
next authorized engineering object = NONE by this failed validation record.
```
