# Database-backed IS implementation

Python standard-library implementation of accepted Design Package v0.1 §4.
This is a storage carrier only: it contains no experiment semantics, no
equivalence adjudication, and no campaign orchestration.

## Files

- `db_is.py`: carrier API and SQLite-backed implementation.
- `schema.sql`: exact accepted DDL.
- `selfcheck.py`: fail-closed storage selfcheck.

## API

```python
from db_is import DatabaseBackedIS

carrier = DatabaseBackedIS.init_empty(path)

with carrier.transaction():
    object_id = carrier.write_object(b"object bytes")
    carrier.append_index_entry({
        "srs_identity": "example-srs",
        "record_object": object_id,
    })
    carrier.append_dependency_entry({
        "dependency_id": "D-1",
        "content_address": object_id,
        "revision": 1,
        "reason": "initial",
    })

content = carrier.get_object(object_id)
srs = carrier.resolve_srs_identity("example-srs")
current = carrier.resolve_current_dependency("D-1")
history = carrier.dependency_history("D-1")
ok = carrier.verify_object(object_id)
carrier.close()
```

## Contract

- `object_id = lowercase hex SHA256(content)`.
- Writing the same bytes to the same object ID is idempotent.
- Divergent stored bytes under an object ID raise `ObjectByteMismatch`.
- Objects are immutable after creation.
- SRS identity resolution is first match in append order.
- Dependency current resolution is LAST match in append order.
- Dependency history is append-only.
- API transactions provide atomic logical write groups.
- The carrier exposes no update/delete methods.

## Non-goals

No campaign behavior, equivalence adjudication, logical import, PALACE
integration, production integration, or broader carrier claim.
