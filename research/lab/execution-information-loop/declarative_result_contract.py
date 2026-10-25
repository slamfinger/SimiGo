"""Declarative result-contract engine for the production model-result gate.

A model task declares, in its OWN item payload, how the generated text becomes a
settled result: which fields are required, how each field is extracted and
typed, which already-admitted input bindings a field must agree with, and how
fields derive from each other. Validation reads that declaration and nothing
else -- the entry points here never receive a task item id, so no task can be
routed into another task's semantics by name.

Two entry points:

``validate_result_text(text, contract, verified_bindings)``
    Pure contract evaluation. ``verified_bindings`` must be values resolved by
    the production admission path, not values computed by a harness.

``validate_declared_result(source_payload, value, dependency_values)``
    The production gate used by ``execute-with-model-result``. It resolves the
    verified bindings out of the admitted dependency closure using the item's
    own declared binding selectors, validates the producer's raw generated text
    against the declared contract, and cross-checks that every structured field
    the producer reported is the value the contract extracts from that same
    text.

Every unknown schema version, unknown field type, unknown constraint, ambiguous
match or missing required field fails closed with a structured
:class:`ContractError`; the caller refuses settlement and therefore never signs.

Reference behaviour, constraint vocabulary and the fail-closed ordering follow
the J-round reference implementation that ships with the task pack; the
production additions are binding *resolution* (``bindings`` selectors, so the
rules stay item-id-free) and two derivation constraints the H-round chain needs
(``digest_equals_binding``, ``equals_binding_segment``).
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import re
from typing import Any, Mapping

CONTRACT_VERSION = "simigo.result-contract/v1"
LEGACY_EXTRACTION_VERSION = "simigo.result-extraction/legacy-v1"


@dataclass(frozen=True)
class ContractError(ValueError):
    code: str
    detail: str
    field: str | None = None

    def __str__(self) -> str:
        where = f" field={self.field}" if self.field else ""
        return f"{self.code}:{where} {self.detail}".strip()


def canonical(value: Any) -> bytes:
    """The same canonical encoding the carrier uses for settlement digests."""
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True,
        separators=(",", ":")).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def _typed(value: str, field: str, spec: Mapping[str, Any]) -> Any:
    kind = spec.get("type", "string")
    if kind == "string":
        value = value.strip()
        normalizer = spec.get("normalize", "trim")
        if normalizer == "upper":
            value = value.upper()
        elif normalizer == "lower":
            value = value.lower()
        elif normalizer != "trim":
            raise ContractError(
                "CONTRACT_UNKNOWN_NORMALIZER",
                f"unsupported normalizer {normalizer!r}", field)
        if spec.get("nonempty", True) and not value:
            raise ContractError(
                "CONTRACT_EMPTY_FIELD", "field must be non-empty", field)
        return value
    if kind == "integer":
        try:
            n = int(value.strip(), 10)
        except (TypeError, ValueError) as e:
            raise ContractError(
                "CONTRACT_TYPE_MISMATCH", "expected base-10 integer",
                field) from e
        if "minimum" in spec and n < spec["minimum"]:
            raise ContractError(
                "CONTRACT_RANGE_VIOLATION", f"{n} < minimum {spec['minimum']}",
                field)
        if "maximum" in spec and n > spec["maximum"]:
            raise ContractError(
                "CONTRACT_RANGE_VIOLATION", f"{n} > maximum {spec['maximum']}",
                field)
        return n
    if kind == "boolean":
        v = value.strip().lower()
        if v in ("true", "1", "yes"):
            return True
        if v in ("false", "0", "no"):
            return False
        raise ContractError(
            "CONTRACT_TYPE_MISMATCH", "expected boolean literal", field)
    if kind == "enum":
        v = value.strip()
        choices = spec.get("values")
        if not isinstance(choices, list) or not choices:
            raise ContractError(
                "CONTRACT_INVALID_FIELD_SPEC",
                "enum field requires a non-empty values list", field)
        if v not in choices:
            raise ContractError(
                "CONTRACT_ENUM_VIOLATION",
                f"value {v!r} is not in declared enum", field)
        return v
    raise ContractError(
        "CONTRACT_UNKNOWN_FIELD_TYPE", f"unsupported field type {kind!r}", field)


def _extract(text: str, field: str, spec: Mapping[str, Any]) -> Any:
    pattern = spec.get("pattern")
    if not isinstance(pattern, str) or not pattern:
        raise ContractError(
            "CONTRACT_INVALID_FIELD_SPEC",
            "field requires a non-empty extraction pattern", field)
    try:
        compiled = re.compile(pattern, re.MULTILINE)
    except re.error as e:
        raise ContractError("CONTRACT_INVALID_PATTERN", str(e), field) from e
    matches = list(compiled.finditer(text))
    if not matches:
        if spec.get("required", True):
            raise ContractError(
                "PRODUCER_RESULT_FIELD_MISSING",
                "required field was not present in generated text", field)
        return None
    policy = spec.get("match_policy", "exactly_one")
    if policy not in ("exactly_one", "first"):
        raise ContractError(
            "CONTRACT_INVALID_FIELD_SPEC",
            f"unsupported match_policy {policy!r}", field)
    if policy == "exactly_one" and len(matches) != 1:
        raise ContractError(
            "CONTRACT_AMBIGUOUS_FIELD",
            f"expected one match, found {len(matches)}", field)
    match = matches[0]
    group = spec.get("capture_group", 1)
    try:
        raw = match.group(group)
    except (IndexError, KeyError, TypeError) as e:
        raise ContractError(
            "CONTRACT_INVALID_PATTERN", f"capture group {group!r} not present",
            field) from e
    if raw is None:
        if spec.get("required", True):
            raise ContractError(
                "PRODUCER_RESULT_FIELD_MISSING",
                "capture group produced no value", field)
        return None
    return _typed(raw, field, spec)


def _resolve_part(name: str, values: Mapping[str, Any],
                  bindings: Mapping[str, Any]) -> Any:
    """A named part is this item's own extracted field, else a verified binding."""
    if name in values:
        return values[name]
    if name in bindings:
        return bindings[name]
    raise ContractError(
        "CONTRACT_INVALID_CONSTRAINT",
        f"part {name!r} is neither a declared field nor a verified binding")


def _check_constraints(values: Mapping[str, Any], constraints: Any,
                       bindings: Mapping[str, Any]) -> list[dict[str, Any]]:
    if constraints is None:
        constraints = []
    if not isinstance(constraints, list):
        raise ContractError(
            "CONTRACT_INVALID_SCHEMA", "constraints must be a list")
    trace: list[dict[str, Any]] = []
    for index, c in enumerate(constraints):
        if not isinstance(c, dict):
            raise ContractError(
                "CONTRACT_INVALID_CONSTRAINT",
                f"constraint {index} must be an object")
        kind = c.get("kind")
        field = c.get("field")
        if field not in values:
            raise ContractError(
                "CONTRACT_CONSTRAINT_FIELD_MISSING",
                f"constraint {index} references absent field", str(field))
        actual = values[field]
        if kind == "equals_binding":
            binding_name = c.get("binding")
            if binding_name not in bindings:
                raise ContractError(
                    "CONTRACT_BINDING_MISSING",
                    f"required verified binding {binding_name!r} is absent",
                    str(field))
            expected = bindings[binding_name]
            if actual != expected:
                raise ContractError(
                    "PRODUCER_RESULT_BINDING_MISMATCH",
                    f"actual {actual!r} != bound value {expected!r}", str(field))
            trace.append({"index": index, "kind": kind, "field": field,
                          "binding": binding_name, "passed": True})
        elif kind == "concat":
            parts = c.get("parts")
            separator = c.get("separator", "")
            if not isinstance(parts, list) or not parts:
                raise ContractError(
                    "CONTRACT_INVALID_CONSTRAINT",
                    f"constraint {index} has no concat parts", str(field))
            resolved = [_resolve_part(p, values, bindings) for p in parts]
            expected = separator.join(str(part) for part in resolved)
            if actual != expected:
                raise ContractError(
                    "PRODUCER_RESULT_DERIVATION_MISMATCH",
                    f"actual {actual!r} != derived value {expected!r}",
                    str(field))
            trace.append({"index": index, "kind": kind, "field": field,
                          "parts": parts, "passed": True})
        elif kind == "equals_field":
            other = c.get("other_field")
            if other not in values:
                raise ContractError(
                    "CONTRACT_INVALID_CONSTRAINT",
                    f"constraint {index} references absent other_field",
                    str(field))
            if actual != values[other]:
                raise ContractError(
                    "PRODUCER_RESULT_FIELD_MISMATCH",
                    f"{actual!r} != {other}={values[other]!r}", str(field))
            trace.append({"index": index, "kind": kind, "field": field,
                          "other_field": other, "passed": True})
        elif kind == "equals_literal":
            expected = c.get("value")
            if actual != expected:
                raise ContractError(
                    "PRODUCER_RESULT_LITERAL_MISMATCH",
                    f"actual {actual!r} != declared literal {expected!r}",
                    str(field))
            trace.append({"index": index, "kind": kind, "field": field,
                          "passed": True})
        elif kind == "digest_equals_binding":
            # The field's own canonical digest must equal a verified binding,
            # i.e. the generated value commits to something already settled.
            binding_name = c.get("binding")
            if binding_name not in bindings:
                raise ContractError(
                    "CONTRACT_BINDING_MISSING",
                    f"required verified binding {binding_name!r} is absent",
                    str(field))
            expected = bindings[binding_name]
            if digest(actual) != expected:
                raise ContractError(
                    "PRODUCER_RESULT_DERIVATION_MISMATCH",
                    f"digest of {actual!r} != bound commitment", str(field))
            trace.append({"index": index, "kind": kind, "field": field,
                          "binding": binding_name, "passed": True})
        elif kind == "equals_binding_segment":
            # A segment of a verified binding string, e.g. the secret half of a
            # composed "<secret>-<checksum>" answer.
            binding_name = c.get("binding")
            separator = c.get("separator")
            segment = c.get("segment", 0)
            if binding_name not in bindings:
                raise ContractError(
                    "CONTRACT_BINDING_MISSING",
                    f"required verified binding {binding_name!r} is absent",
                    str(field))
            if not isinstance(separator, str) or not separator:
                raise ContractError(
                    "CONTRACT_INVALID_CONSTRAINT",
                    f"constraint {index} needs a non-empty separator",
                    str(field))
            raw = bindings[binding_name]
            if not isinstance(raw, str):
                raise ContractError(
                    "PRODUCER_RESULT_DERIVATION_MISMATCH",
                    f"bound value for {binding_name!r} is not text", str(field))
            pieces = raw.split(separator)
            if not isinstance(segment, int) or segment >= len(pieces):
                raise ContractError(
                    "CONTRACT_INVALID_CONSTRAINT",
                    f"constraint {index} selects a missing segment", str(field))
            if actual != pieces[segment]:
                raise ContractError(
                    "PRODUCER_RESULT_DERIVATION_MISMATCH",
                    f"actual {actual!r} != segment {segment} of bound value",
                    str(field))
            trace.append({"index": index, "kind": kind, "field": field,
                          "binding": binding_name, "segment": segment,
                          "passed": True})
        else:
            raise ContractError(
                "CONTRACT_UNKNOWN_CONSTRAINT",
                f"unsupported constraint kind {kind!r}", str(field))
    return trace


def validate_result_text(text: str, contract: Mapping[str, Any],
                         verified_bindings: Mapping[str, Any]) -> dict[str, Any]:
    """Parse and validate a generated result using only its declared contract.

    No item ID is accepted as an argument by design. ``verified_bindings`` must
    be values resolved and validated by the production admission path.
    """
    if not isinstance(text, str):
        raise ContractError("CONTRACT_INVALID_INPUT", "generated result must be text")
    if not isinstance(contract, Mapping):
        raise ContractError("CONTRACT_INVALID_SCHEMA", "contract must be an object")
    if contract.get("schema_version") != CONTRACT_VERSION:
        raise ContractError(
            "CONTRACT_UNKNOWN_SCHEMA_VERSION", f"expected {CONTRACT_VERSION!r}")
    fields = contract.get("fields")
    if not isinstance(fields, Mapping) or not fields:
        raise ContractError(
            "CONTRACT_INVALID_SCHEMA", "fields must be a non-empty object")
    if not isinstance(verified_bindings, Mapping):
        raise ContractError(
            "CONTRACT_INVALID_BINDINGS", "verified_bindings must be an object")
    values: dict[str, Any] = {}
    extraction: dict[str, Any] = {}
    for field, spec in fields.items():
        if not isinstance(field, str) or not isinstance(spec, Mapping):
            raise ContractError(
                "CONTRACT_INVALID_FIELD_SPEC",
                "each field must map to an object", str(field))
        values[field] = _extract(text, field, spec)
        extraction[field] = {
            "required": spec.get("required", True),
            "match_policy": spec.get("match_policy", "exactly_one"),
            "type": spec.get("type", "string"),
            "parsed": values[field] is not None,
        }
    constraints = _check_constraints(
        values, contract.get("constraints", []), verified_bindings)
    return {
        "schema_version": CONTRACT_VERSION,
        "values": values,
        "field_extraction": extraction,
        "constraint_checks": constraints,
        "bindings_used": sorted(
            {c["binding"] for c in constraints if "binding" in c}),
        "validation_status": "VALID",
    }


def resolve_verified_bindings(contract: Mapping[str, Any],
                              source_payload: Mapping[str, Any],
                              dependency_values: Mapping[str, Any]) -> dict[str, Any]:
    """Project the admitted dependency values into named verified bindings.

    Selectors are declared by the item itself and name NO validation rule:

      {"name": n, "source": "input_binding", "placeholder": p}
          the value bound to the item's declared input placeholder ``p`` (its
          declared dependency item and result field), taken from the admitted
          closure ``dependency_values``.
      {"name": n, "source": "dependency_field", "field": f}
          the value of settled field ``f``; exactly one admitted dependency
          must provide it, otherwise the binding is refused.
    """
    specs = contract.get("bindings", [])
    if specs is None:
        specs = []
    if not isinstance(specs, list):
        raise ContractError(
            "CONTRACT_INVALID_SCHEMA", "bindings must be a list")
    input_bindings = {}
    declared = source_payload.get("input_bindings") if isinstance(
        source_payload, Mapping) else None
    if isinstance(declared, list):
        for row in declared:
            if isinstance(row, Mapping) and isinstance(row.get("placeholder"), str):
                input_bindings[row["placeholder"]] = row
    resolved: dict[str, Any] = {}
    trace: list[dict[str, Any]] = []
    for index, spec in enumerate(specs):
        if not isinstance(spec, Mapping) or not isinstance(spec.get("name"), str):
            raise ContractError(
                "CONTRACT_INVALID_BINDING_SPEC",
                f"binding {index} must name a binding", str(index))
        name = spec["name"]
        source = spec.get("source")
        if name in resolved:
            raise ContractError(
                "CONTRACT_DUPLICATE_BINDING", f"binding {name!r} declared twice",
                name)
        if source == "input_binding":
            placeholder = spec.get("placeholder")
            row = input_bindings.get(placeholder)
            if row is None:
                raise ContractError(
                    "CONTRACT_BINDING_MISSING",
                    f"input placeholder {placeholder!r} is not declared by the item",
                    name)
            provider = row.get("item_id")
            field = row.get("result_field")
            value = dependency_values.get(provider) if isinstance(
                dependency_values, Mapping) else None
            if not isinstance(value, Mapping) or field not in value:
                raise ContractError(
                    "CONTRACT_BINDING_NOT_ADMITTED",
                    f"declared placeholder {placeholder!r} resolves to no admitted "
                    f"settled field {field!r} of {provider!r}", name)
            resolved[name] = value[field]
            trace.append({"index": index, "name": name, "source": source,
                          "placeholder": placeholder, "result_field": field})
        elif source == "dependency_field":
            field = spec.get("field")
            if not isinstance(field, str) or not field:
                raise ContractError(
                    "CONTRACT_INVALID_BINDING_SPEC",
                    f"binding {index} needs a field name", name)
            providers = [dep for dep, val in
                         (dependency_values or {}).items()
                         if isinstance(val, Mapping) and field in val]
            if len(providers) != 1:
                raise ContractError(
                    "CONTRACT_AMBIGUOUS_BINDING_SOURCE",
                    f"field {field!r} is provided by {len(providers)} admitted "
                    "dependencies; exactly one is required", name)
            resolved[name] = dependency_values[providers[0]][field]
            trace.append({"index": index, "name": name, "source": source,
                          "result_field": field})
        else:
            raise ContractError(
                "CONTRACT_UNKNOWN_BINDING_SOURCE",
                f"unsupported binding source {source!r}", name)
    return {"bindings": resolved, "resolution": trace}


def declared_contract(source_payload: Mapping[str, Any]) -> Mapping[str, Any]:
    """Read the item's own declarative contract, failing closed when absent."""
    if not isinstance(source_payload, Mapping):
        raise ContractError(
            "CONTRACT_INVALID_INPUT", "task source payload must be an object")
    contract = source_payload.get("semantic_contract")
    if not isinstance(contract, Mapping):
        raise ContractError(
            "PRODUCER_RESULT_CONTRACT_UNDECLARED",
            "the task item declares no declarative result contract; settlement "
            "is refused rather than guessed from the item id")
    if contract.get("schema_version") != CONTRACT_VERSION:
        raise ContractError(
            "CONTRACT_UNKNOWN_SCHEMA_VERSION",
            f"expected {CONTRACT_VERSION!r}, found "
            f"{contract.get('schema_version')!r}")
    return contract


def derive_extraction_view(contract: Mapping[str, Any]) -> dict[str, Any]:
    """Legacy Swift-facing extraction view derived from the declarative contract.

    The frozen native binary reads ``result_contract.fields`` as a
    ``[{name, pattern}]`` list. This adapter derives that view from the single
    authoritative declarative contract so the two can never drift; it is
    explicitly versioned and selected by declared schema version, never by an
    item id.
    """
    fields = contract.get("fields")
    if not isinstance(fields, Mapping):
        raise ContractError(
            "CONTRACT_INVALID_SCHEMA", "fields must be an object")
    view = []
    for name, spec in fields.items():
        if not isinstance(spec, Mapping) or not isinstance(
                spec.get("pattern"), str):
            raise ContractError(
                "CONTRACT_INVALID_FIELD_SPEC",
                f"field {name!r} needs a pattern for the extraction view", name)
        view.append({"name": name, "pattern": spec["pattern"]})
    return {"schema_version": LEGACY_EXTRACTION_VERSION, "fields": view}


def validate_declared_result(source_payload: Mapping[str, Any],
                             value: Mapping[str, Any],
                             dependency_values: Mapping[str, Any]) -> dict[str, Any]:
    """The production result gate: item-declared contract, zero task-id rules.

    Rejects, in order: an undeclared/unknown contract, a producer value that
    carries no generated text or no generated tokens, contract extraction
    failures (missing/ambiguous/mistyped fields), binding resolution failures,
    constraint failures, and finally any structured field the producer reported
    that disagrees with what its own text says.
    """
    contract = declared_contract(source_payload)
    if not isinstance(value, Mapping):
        raise ContractError("CONTRACT_INVALID_INPUT", "model value must be an object")
    generated_tokens = value.get("generated_token_ids")
    if not isinstance(generated_tokens, list) or not generated_tokens:
        raise ContractError(
            "CONTRACT_INVALID_INPUT", "model value carries no generated tokens")
    if not isinstance(value.get("model_snapshot_revision"), str) or not value[
            "model_snapshot_revision"]:
        raise ContractError(
            "CONTRACT_INVALID_INPUT",
            "model value carries no model snapshot identity")
    text = value.get("raw_generated_text")
    if not isinstance(text, str) or not text:
        raise ContractError(
            "CONTRACT_INVALID_INPUT",
            "model value carries no raw generated text for the declared contract")
    if not isinstance(dependency_values, Mapping):
        raise ContractError(
            "CONTRACT_INVALID_BINDINGS", "admitted dependency values must be an object")
    resolution = resolve_verified_bindings(
        contract, source_payload, dependency_values)
    report = validate_result_text(text, contract, resolution["bindings"])
    mismatches = {}
    for name, extracted in report["values"].items():
        if name in value and value[name] != extracted:
            mismatches[name] = {"producer_reported": value[name],
                                "contract_extracted": extracted}
    if mismatches:
        raise ContractError(
            "PRODUCER_RESULT_VALUE_TEXT_DISAGREEMENT",
            "reported structured fields disagree with the declared contract "
            "applied to the generated text: %s" % sorted(mismatches))
    report["binding_resolution"] = resolution["resolution"]
    report["verified_binding_names"] = sorted(resolution["bindings"])
    return report
