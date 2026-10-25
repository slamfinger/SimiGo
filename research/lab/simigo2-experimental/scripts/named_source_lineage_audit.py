#!/usr/bin/env python3
"""Audit GGUF/MLX tokenizer and declared lineage for a named-source pair.

The audit establishes tokenizer substrate and declared model lineage. It does
not establish same-checkpoint identity: different quantized payloads can share
lineage and tokenizer while having different bytes and numerics.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_string(handle) -> bytes:
    length = struct.unpack("<Q", handle.read(8))[0]
    return handle.read(length)


def read_value(handle, value_type: int):
    if value_type == 0:
        return struct.unpack("<B", handle.read(1))[0]
    if value_type == 1:
        return struct.unpack("<b", handle.read(1))[0]
    if value_type == 2:
        return struct.unpack("<H", handle.read(2))[0]
    if value_type == 3:
        return struct.unpack("<h", handle.read(2))[0]
    if value_type == 4:
        return struct.unpack("<I", handle.read(4))[0]
    if value_type == 5:
        return struct.unpack("<i", handle.read(4))[0]
    if value_type == 6:
        return struct.unpack("<f", handle.read(4))[0]
    if value_type == 7:
        return bool(handle.read(1)[0])
    if value_type == 8:
        return read_string(handle)
    if value_type == 9:
        element_type = struct.unpack("<I", handle.read(4))[0]
        count = struct.unpack("<Q", handle.read(8))[0]
        return [read_value(handle, element_type) for _ in range(count)]
    if value_type == 10:
        return struct.unpack("<Q", handle.read(8))[0]
    if value_type == 11:
        return struct.unpack("<q", handle.read(8))[0]
    if value_type == 12:
        return struct.unpack("<d", handle.read(8))[0]
    raise ValueError(f"unsupported GGUF metadata type: {value_type}")


def parse_gguf_metadata(path: Path) -> tuple[dict, int, int, int]:
    with path.open("rb") as handle:
        magic = handle.read(4)
        if magic != b"GGUF":
            raise ValueError("not a GGUF file")
        version = struct.unpack("<I", handle.read(4))[0]
        tensor_count, metadata_count = struct.unpack("<QQ", handle.read(16))
        metadata: dict[str, object] = {}
        for _ in range(metadata_count):
            key = read_string(handle).decode("utf-8", "replace")
            value_type = struct.unpack("<I", handle.read(4))[0]
            metadata[key] = read_value(handle, value_type)
    def decode_bytes(value):
        if isinstance(value, bytes):
            return value.decode("utf-8", "replace")
        if isinstance(value, list):
            return [decode_bytes(item) for item in value]
        return value

    metadata = {key: decode_bytes(value) for key, value in metadata.items()}
    return metadata, version, tensor_count, metadata_count


def normalized_architecture(value: str) -> str:
    return value.replace("_", "").lower()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gguf", required=True)
    parser.add_argument("--mlx-dir", required=True)
    parser.add_argument("--source-compare", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    gguf_path = Path(args.gguf).resolve()
    mlx_dir = Path(args.mlx_dir).resolve()
    metadata, gguf_version, gguf_tensor_count, gguf_metadata_count = parse_gguf_metadata(gguf_path)

    tokenizer_path = mlx_dir / "tokenizer.json"
    vocab_path = mlx_dir / "vocab.json"
    merges_path = mlx_dir / "merges.txt"
    config_path = mlx_dir / "config.json"
    chat_template_path = mlx_dir / "chat_template.jinja"

    tokenizer_json = json.loads(tokenizer_path.read_text())
    vocab = tokenizer_json["model"]["vocab"]
    inverse_vocab = {token_id: token for token, token_id in vocab.items()}
    added_tokens = {entry["id"]: entry["content"] for entry in tokenizer_json["added_tokens"]}
    mlx_merges = [
        tuple(piece.split(" "))
        for piece in tokenizer_json["model"]["merges"]
    ]

    gguf_tokens = metadata["tokenizer.ggml.tokens"]
    gguf_token_types = metadata["tokenizer.ggml.token_type"]
    gguf_merges = [
        tuple(piece.split(" "))
        for piece in metadata["tokenizer.ggml.merges"]
    ]

    base_vocab_count = len(vocab)
    added_token_count = len(added_tokens)
    expected_total = base_vocab_count + added_token_count
    gguf_token_count = len(gguf_tokens)

    base_vocab_mismatches = []
    for token_id in range(min(base_vocab_count, gguf_token_count)):
        gguf_token = gguf_tokens[token_id]
        hf_token = inverse_vocab.get(token_id)
        if hf_token != gguf_token:
            base_vocab_mismatches.append(
                {"id": token_id, "mlx": hf_token, "gguf": gguf_token}
            )
            if len(base_vocab_mismatches) >= 20:
                break

    added_token_mismatches = []
    for offset in range(added_token_count):
        token_id = base_vocab_count + offset
        if token_id >= gguf_token_count:
            added_token_mismatches.append({"id": token_id, "reason": "MISSING_IN_GGUF"})
            break
        if added_tokens.get(token_id) != gguf_tokens[token_id]:
            added_token_mismatches.append(
                {"id": token_id, "mlx": added_tokens.get(token_id), "gguf": gguf_tokens[token_id]}
            )
            if len(added_token_mismatches) >= 20:
                break

    merge_mismatches = []
    merge_check_count = min(len(mlx_merges), len(gguf_merges))
    for merge_id in range(merge_check_count):
        if mlx_merges[merge_id] != gguf_merges[merge_id]:
            merge_mismatches.append(
                {
                    "id": merge_id,
                    "mlx": list(mlx_merges[merge_id]),
                    "gguf": list(gguf_merges[merge_id]),
                }
            )
            if len(merge_mismatches) >= 20:
                break

    extra_tokens = [
        {
            "id": token_id,
            "token": gguf_tokens[token_id],
            "type": gguf_token_types[token_id],
        }
        for token_id in range(expected_total, gguf_token_count)
    ]

    source = json.loads(Path(args.source_compare).read_text())
    used_token_ids = {
        token_id
        for case in source["cases"]
        for token_id in case["promptTokenIDs"] + case["mlxGeneratedTokenIDs"] + case["llamaGeneratedTokenIDs"]
    }
    shared_vocab_limit = expected_total
    used_ids_outside_shared_vocab = sorted(
        token_id for token_id in used_token_ids if token_id >= shared_vocab_limit
    )

    gguf_architecture = metadata.get("general.architecture")
    mlx_config = json.loads(config_path.read_text())
    mlx_architecture = mlx_config.get("model_type")
    architecture_match = normalized_architecture(gguf_architecture) == normalized_architecture(mlx_architecture)
    tokenizer_model_match = metadata.get("tokenizer.ggml.model") == "gpt2" and tokenizer_json["model"]["type"] == "BPE"
    base_vocab_match = not base_vocab_mismatches and base_vocab_count <= gguf_token_count
    added_token_match = not added_token_mismatches
    merges_match = len(mlx_merges) == len(gguf_merges) and not merge_mismatches

    mlx_template = chat_template_path.read_text() if chat_template_path.exists() else None
    gguf_template = metadata.get("tokenizer.chat_template")
    chat_template_match = mlx_template is not None and mlx_template == gguf_template

    mlx_base_from_readme = None
    readme_path = mlx_dir / "README.md"
    if readme_path.exists():
        for line in readme_path.read_text().splitlines():
            stripped = line.strip()
            if stripped.startswith("- ") and "Huihui-Ornith" in stripped:
                mlx_base_from_readme = stripped.removeprefix("- ").strip()
                break

    gguf_base_name = metadata.get("general.base_model.0.name")
    gguf_base_url = metadata.get("general.base_model.0.repo_url")
    gguf_basename = metadata.get("general.basename")
    # The artifacts declare a two-hop lineage:
    #   Ornith 1.5 -> Huihui-Ornith-1.5 abliterated -> CyberTiel quantization.
    # Therefore direct equality is not expected. GGUF must identify the
    # Huihui-Ornith abliterated substrate and its upstream Ornith base; MLX
    # README must identify the same Huihui-Ornith abliterated substrate.
    gguf_substrate_match = (
        "Huihui-Ornith-1.5" in str(gguf_basename)
        and ("Huihui Ornith 1.5" in str(metadata.get("general.name"))
             or "Huihui-Ornith-1.5" in str(metadata.get("general.name")))
        and metadata.get("general.finetune") == "abliterated"
    )
    gguf_upstream_match = (
        ("Ornith-1.5-35B-A3B" in str(gguf_base_name)
         or "Ornith 1.5 35B A3B" in str(gguf_base_name))
        and "ornith-ai/Ornith-1.5-35B-A3B" in str(gguf_base_url)
    )
    mlx_substrate_match = (
        mlx_base_from_readme is not None
        and "huihui-ai/Huihui-Ornith-1.5-35B-A3B-abliterated" in mlx_base_from_readme
    )
    source_metadata_match = gguf_substrate_match and gguf_upstream_match and mlx_substrate_match

    checks = {
        "GGUF_VERSION_SUPPORTED": gguf_version == 3,
        "ARCHITECTURE_NORMALIZED_MATCH": architecture_match,
        "TOKENIZER_MODEL_MATCH": tokenizer_model_match,
        "BASE_VOCAB_EXACT": base_vocab_match,
        "ADDED_TOKENS_EXACT": added_token_match,
        "MERGES_EXACT": merges_match,
        "CHAT_TEMPLATE_EXACT": chat_template_match,
        "SOURCE_LINEAGE_CHAIN_MATCH": source_metadata_match,
        "MATRIX_IDS_WITHIN_SHARED_VOCAB": not used_ids_outside_shared_vocab,
    }

    substrate_pass = all(
        checks[key]
        for key in [
            "GGUF_VERSION_SUPPORTED",
            "ARCHITECTURE_NORMALIZED_MATCH",
            "TOKENIZER_MODEL_MATCH",
            "BASE_VOCAB_EXACT",
            "ADDED_TOKENS_EXACT",
            "MERGES_EXACT",
            "CHAT_TEMPLATE_EXACT",
            "MATRIX_IDS_WITHIN_SHARED_VOCAB",
        ]
    )

    result = {
        "status": "PASS_WITH_BOUNDARY" if substrate_pass and source_metadata_match else "FAIL",
        "protocolVersion": "LAB.NAMED_SOURCE.LINEAGE.AUDIT.V1",
        "boundary": "TOKENIZER_AND_DECLARED_LINEAGE_AUDIT / NO_WEIGHT_BYTES_COMPARED / NO_SAME_CHECKPOINT_CLAIM",
        "gguf": {
            "path": str(gguf_path),
            "sizeBytes": gguf_path.stat().st_size,
            "version": gguf_version,
            "tensorCount": gguf_tensor_count,
            "metadataCount": gguf_metadata_count,
            "generalName": metadata.get("general.name"),
            "generalBasename": metadata.get("general.basename"),
            "generalFinetune": metadata.get("general.finetune"),
            "generalArchitecture": gguf_architecture,
            "baseModelName": gguf_base_name,
            "baseModelOrganization": metadata.get("general.base_model.0.organization"),
            "baseModelUrl": gguf_base_url,
            "tokenizerModel": metadata.get("tokenizer.ggml.model"),
            "tokenizerPre": metadata.get("tokenizer.ggml.pre"),
        },
        "mlx": {
            "path": str(mlx_dir),
            "architecture": mlx_architecture,
            "tokenizerJsonSHA256": sha256(tokenizer_path),
            "vocabJsonSHA256": sha256(vocab_path) if vocab_path.exists() else None,
            "mergesTxtSHA256": sha256(merges_path) if merges_path.exists() else None,
            "chatTemplateJinjaSHA256": sha256(chat_template_path) if chat_template_path.exists() else None,
            "readmeBaseModel": mlx_base_from_readme,
        },
        "tokenizerSubstrate": {
            "ggufTokenCount": gguf_token_count,
            "mlxBaseVocabCount": base_vocab_count,
            "mlxAddedTokenCount": added_token_count,
            "mlxExpectedTotalCount": expected_total,
            "ggufExtraTokenCount": gguf_token_count - expected_total,
            "ggufMergeCount": len(gguf_merges),
            "mlxMergeCount": len(mlx_merges),
            "sharedBaseVocabCount": base_vocab_count,
            "sharedAddedTokenCount": added_token_count,
            "sharedMergeCount": merge_check_count,
            "baseVocabMismatchCount": len(base_vocab_mismatches),
            "addedTokenMismatchCount": len(added_token_mismatches),
            "mergeMismatchCount": len(merge_mismatches),
            "chatTemplateExact": chat_template_match,
            "extraTokenSample": extra_tokens[:30],
            "extraTokenCategories": {
                "control": sum(1 for token in extra_tokens if token["type"] == 3),
                "padding": sum(1 for token in extra_tokens if token["type"] == 5),
            },
        },
        "matrixUsage": {
            "sourceComparePath": str(Path(args.source_compare).resolve()),
            "sourceCompareSHA256": sha256(Path(args.source_compare)),
            "usedUniqueTokenIDCount": len(used_token_ids),
            "maxUsedTokenID": max(used_token_ids) if used_token_ids else None,
            "sharedVocabLimit": shared_vocab_limit,
            "usedIDsOutsideSharedVocab": used_ids_outside_shared_vocab,
        },
        "lineage": {
            "architectureNormalizedMatch": architecture_match,
            "ggufDeclaredBase": {
                "name": gguf_base_name,
                "organization": metadata.get("general.base_model.0.organization"),
                "url": gguf_base_url,
            },
            "mlxReadmeDeclaredBase": mlx_base_from_readme,
            "publicationAlias": "CyberTiel",
            "lineageChain": "Ornith 1.5 -> Huihui-Ornith-1.5-abliterated -> CyberTiel quantization",
            "ggufSubstrateMatch": gguf_substrate_match,
            "ggufUpstreamMatch": gguf_upstream_match,
            "mlxSubstrateMatch": mlx_substrate_match,
            "sourceMetadataMatch": source_metadata_match,
            "checkpointIdentity": "OPEN / WEIGHT_BYTES_NOT_COMPARED",
        },
        "checks": checks,
        "substratePass": substrate_pass,
        "overallPass": substrate_pass and source_metadata_match,
    }
    Path(args.output).write_text(
        json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    )


if __name__ == "__main__":
    main()
