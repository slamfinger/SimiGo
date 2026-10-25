# Integrated ES–PALACE D001 preparation implementation

Preparation-only, deterministic, Python-standard-library implementation for
Authorization Package v1.0. It validates seven isolated fixture cases and does
not execute an integrated experiment.

Run:

```bash
python3 integrated-es-palace/d001/implementation/preflight.py --manifest docs/02-evidence/integrated-es-palace-d001-validation-v1/RUN_MANIFEST_INSTANCE.json
python3 integrated-es-palace/d001/implementation/selfcheck.py --manifest docs/02-evidence/integrated-es-palace-d001-validation-v1/RUN_MANIFEST_INSTANCE.json --stage S1-FIXTURE_PREPARATION
python3 integrated-es-palace/d001/implementation/selfcheck.py --manifest docs/02-evidence/integrated-es-palace-d001-validation-v1/RUN_MANIFEST_INSTANCE.json --stage S2-PREPARATION_VALIDATION
```

Forbidden: network, models, ranking, environment input, canonical IS mutation,
E9, EXP-004, PIR reopening, and equivalence claims.
