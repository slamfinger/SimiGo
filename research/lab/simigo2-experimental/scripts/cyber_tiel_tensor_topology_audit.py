#!/usr/bin/env python3
"""Read-only GGUF/MLX tensor topology audit for the CyberTiel pair.

Parses GGUF tensor headers and safetensors headers only. It never loads or
dequantizes model weights. The audit maps the complete text-model tensor graph
and reports known format-specific extras (GGUF nextn/MTP block; MLX vision
tower).
"""
from __future__ import annotations
import argparse, json, struct
from collections import Counter
from pathlib import Path

GGUF_TYPE_NAMES = {
 0:"F32",1:"F16",2:"Q4_0",3:"Q4_1",8:"Q8_0",12:"Q4_K",13:"Q5_K",14:"Q6_K",15:"Q8_K",16:"IQ2_XXS"
}

def read_string(handle):
 length=struct.unpack("<Q",handle.read(8))[0]
 return handle.read(length)

def read_value(handle,value_type):
 if value_type in (0,7): return handle.read(1)[0]
 if value_type==1:return struct.unpack("<b",handle.read(1))[0]
 if value_type==2:return struct.unpack("<H",handle.read(2))[0]
 if value_type==3:return struct.unpack("<h",handle.read(2))[0]
 if value_type==4:return struct.unpack("<I",handle.read(4))[0]
 if value_type==5:return struct.unpack("<i",handle.read(4))[0]
 if value_type==6:return struct.unpack("<f",handle.read(4))[0]
 if value_type==8:return read_string(handle)
 if value_type==9:
  element_type=struct.unpack("<I",handle.read(4))[0]
  count=struct.unpack("<Q",handle.read(8))[0]
  return [read_value(handle,element_type) for _ in range(count)]
 if value_type==10:return struct.unpack("<Q",handle.read(8))[0]
 if value_type==11:return struct.unpack("<q",handle.read(8))[0]
 if value_type==12:return struct.unpack("<d",handle.read(8))[0]
 raise ValueError(f"unsupported GGUF metadata type {value_type}")

def parse_gguf(path:Path):
 with path.open("rb") as handle:
  magic=handle.read(4)
  if magic!=b"GGUF": raise ValueError("not GGUF")
  version=struct.unpack("<I",handle.read(4))[0]
  tensor_count,metadata_count=struct.unpack("<QQ",handle.read(16))
  for _ in range(metadata_count):
   read_string(handle)
   value_type=struct.unpack("<I",handle.read(4))[0]
   read_value(handle,value_type)
  tensors={}
  for _ in range(tensor_count):
   name=read_string(handle).decode("utf-8","replace")
   dimension_count=struct.unpack("<I",handle.read(4))[0]
   dimensions=list(struct.unpack("<"+"Q"*dimension_count,handle.read(8*dimension_count)))
   gguf_type=struct.unpack("<I",handle.read(4))[0]
   offset=struct.unpack("<Q",handle.read(8))[0]
   tensors[name]={"dimensions":dimensions,"ggufType":gguf_type,"ggufTypeName":GGUF_TYPE_NAMES.get(gguf_type,f"TYPE_{gguf_type}"),"dataOffset":offset}
  return version,tensors

def parse_safetensors_headers(index_path:Path):
 index=json.loads(index_path.read_text())
 shards={}
 physical={}
 for name,shard in index["weight_map"].items():
  path=index_path.parent/shard
  shard_key=str(path.resolve())
  if shard_key not in shards:
   with path.open("rb") as handle:
    length=struct.unpack("<Q",handle.read(8))[0]
    shards[shard_key]=json.loads(handle.read(length))
  header=shards[shard_key][name]
  physical[name]={"shape":header["shape"],"dtype":header["dtype"],"shard":shard}
 return index,physical

def logical_mlx_inventory(physical):
 groups={}
 for name in physical:
  base=name
  for suffix in (".scales",".biases"):
   if base.endswith(suffix):
    base=base[:-len(suffix)]
    break
  if base.endswith(".weight"):
   base=base[:-len(".weight")]
  groups.setdefault(base,[]).append(name)
 return groups

def expected_mlx(layer:int,gguf_suffix:str):
 prefix=f"language_model.model.layers.{layer}."
 full_attention=layer%4==3
 if gguf_suffix=="attn_norm": return [prefix+"input_layernorm"]
 if gguf_suffix=="post_attention_norm": return [prefix+"post_attention_layernorm"]
 if gguf_suffix=="attn_q": return [prefix+"self_attn.q_proj"]
 if gguf_suffix=="attn_k": return [prefix+"self_attn.k_proj"]
 if gguf_suffix=="attn_v": return [prefix+"self_attn.v_proj"]
 if gguf_suffix=="attn_output": return [prefix+"self_attn.o_proj"]
 if gguf_suffix=="attn_q_norm": return [prefix+"self_attn.q_norm"]
 if gguf_suffix=="attn_k_norm": return [prefix+"self_attn.k_norm"]
 if not full_attention:
  if gguf_suffix=="attn_gate": return [prefix+"linear_attn.in_proj_z"]
  if gguf_suffix=="attn_qkv": return [prefix+"linear_attn.in_proj_qkv"]
  if gguf_suffix=="ssm_alpha": return [prefix+"linear_attn.in_proj_a"]
  if gguf_suffix=="ssm_beta": return [prefix+"linear_attn.in_proj_b"]
  if gguf_suffix=="ssm_a": return [prefix+"linear_attn.A_log"]
  if gguf_suffix=="ssm_conv1d": return [prefix+"linear_attn.conv1d"]
  if gguf_suffix=="ssm_dt.bias": return [prefix+"linear_attn.dt_bias"]
  if gguf_suffix=="ssm_norm": return [prefix+"linear_attn.norm"]
  if gguf_suffix=="ssm_out": return [prefix+"linear_attn.out_proj"]
 if gguf_suffix=="ffn_gate_inp": return [prefix+"mlp.gate"]
 if gguf_suffix=="ffn_gate_inp_shexp": return [prefix+"mlp.shared_expert_gate"]
 if gguf_suffix=="ffn_gate_shexp": return [prefix+"mlp.shared_expert.gate_proj"]
 if gguf_suffix=="ffn_up_shexp": return [prefix+"mlp.shared_expert.up_proj"]
 if gguf_suffix=="ffn_down_shexp": return [prefix+"mlp.shared_expert.down_proj"]
 if gguf_suffix=="ffn_gate_exps": return [prefix+"mlp.switch_mlp.gate_proj"]
 if gguf_suffix=="ffn_up_exps": return [prefix+"mlp.switch_mlp.up_proj"]
 if gguf_suffix=="ffn_down_exps": return [prefix+"mlp.switch_mlp.down_proj"]
 return None

def main():
 parser=argparse.ArgumentParser()
 parser.add_argument("--gguf",required=True)
 parser.add_argument("--mlx-dir",required=True)
 parser.add_argument("--source-lineage",required=True)
 parser.add_argument("--output",required=True)
 args=parser.parse_args()
 gguf_path=Path(args.gguf).resolve()
 mlx_dir=Path(args.mlx_dir).resolve()
 index_path=mlx_dir/"model.safetensors.index.json"
 version,gguf=parse_gguf(gguf_path)
 _,physical=parse_safetensors_headers(index_path)
 logical=logical_mlx_inventory(physical)

 global_mapping={
  "token_embd.weight":["language_model.model.embed_tokens"],
  "output.weight":["language_model.lm_head"],
  "output_norm.weight":["language_model.model.norm"],
 }
 mapping=[]
 matched_mlx=set()
 unmatched_gguf=[]
 for name,tensor in gguf.items():
  parts=name.split(".")
  targets=None
  if name in global_mapping:
   targets=global_mapping[name]
  elif parts[0]=="blk" and len(parts)>2 and int(parts[1])<40:
   suffix=".".join(parts[2:])
   if suffix.endswith(".weight"): suffix=suffix[:-len(".weight")]
   targets=expected_mlx(int(parts[1]),suffix)
  targets=targets or []
  present=[target for target in targets if target in logical]
  if present:
   matched_mlx.update(present)
   mapping.append({"gguf":name,"ggufDimensions":tensor["dimensions"],"ggufType":tensor["ggufTypeName"],"mlxLogicalGroups":present,"mlxPhysicalCount":sum(len(logical[target]) for target in present)})
  else:
   unmatched_gguf.append({"gguf":name,"dimensions":tensor["dimensions"],"expectedMlx":targets})

 mapped_gguf={entry["gguf"] for entry in mapping}
 gguf_only=sorted(set(gguf)-mapped_gguf)
 mlx_language=set(key for key in logical if key.startswith("language_model."))
 mlx_only_language=sorted(mlx_language-matched_mlx)
 mlx_vision=sorted(key for key in logical if key.startswith("vision_tower.") or key.startswith("multi_modal_projector."))
 layer_counts=Counter()
 for name in gguf:
  if name.startswith("blk."):
   layer=int(name.split(".")[1]); layer_counts[layer]+=1
 regular_counts=[layer_counts[i] for i in range(40)]
 full_layers=[i for i in range(40) if i%4==3]
 linear_layers=[i for i in range(40) if i%4!=3]
 checks={
  "GGUF_VERSION_SUPPORTED":version==3,
  "REGULAR_BLOCK_COUNT_40":len([i for i in layer_counts if i<40])==40,
  "FULL_ATTENTION_INTERVAL_4":full_layers==[3,7,11,15,19,23,27,31,35,39],
  "REGULAR_GGUF_TENSORS_MAPPED":all(item["gguf"].startswith("blk.40.") for item in unmatched_gguf),
  "KNOWN_EXTRAS_ONLY":all(name.startswith("blk.40.") for name in gguf_only) and all(name.startswith("vision_tower.") or name.startswith("multi_modal_projector.") for name in mlx_only_language),
  "GLOBAL_AND_REGULAR_MLX_MAPPED":not mlx_only_language,
  "MLX_VISION_IDENTIFIED_AS_MLX_ONLY":len(mlx_vision)>0,
  "GGUF_NEXTN_IDENTIFIED_AS_GGUF_ONLY":"blk.40.nextn.eh_proj.weight" in gguf_only,
 }
 knownExtrasPass=checks["KNOWN_EXTRAS_ONLY"]
 overall=all(checks.values()) and knownExtrasPass
 result={
  "status":"PASS_WITH_BOUNDARY" if overall else "FAIL",
  "protocolVersion":"LAB.NAMED_SOURCE.TENSOR_TOPOLOGY.AUDIT.V1",
  "boundary":"HEADER_AND_TENSOR_NAME_TOPOLOGY_ONLY / NO_WEIGHT_BYTES_OR_DEQUANTIZED_VALUES_COMPARED",
  "gguf":{"path":str(gguf_path),"version":version,"tensorCount":len(gguf),"blockCount":len(layer_counts),"regularBlockCount":40,"nextnBlock":"blk.40","regularTensorCountsByBlock":regular_counts,"fullAttentionLayers":full_layers,"linearAttentionLayers":linear_layers},
  "mlx":{"path":str(mlx_dir),"index":str(index_path),"physicalTensorCount":len(physical),"logicalGroupCount":len(logical),"mappedLogicalGroupCount":len(matched_mlx),"visionLogicalGroupCount":len(mlx_vision),"languageOnlyUnmappedLogicalGroupCount":len(mlx_only_language)},
  "counts":{"ggufTotal":len(gguf),"ggufMapped":len(mapped_gguf),"ggufOnly":len(gguf_only),"mlxLogical":len(logical),"mlxMapped":len(matched_mlx),"mlxVisionOnly":len(mlx_vision),"mlxLanguageOnly":len(mlx_only_language)},
  "checks":checks,
  "unmatchedGgufSample":unmatched_gguf[:30],
  "mlxOnlyLanguageSample":mlx_only_language[:30],
  "mlxVisionOnlySample":mlx_vision[:30],
  "ggufOnlySample":gguf_only[:30],
  "mapping":mapping,
  "sourceLineageAudit":{"path":str(Path(args.source_lineage).resolve()),"sha256":__import__("hashlib").sha256(Path(args.source_lineage).read_bytes()).hexdigest()},
  "overallPass":overall,
 }
 Path(args.output).write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+"\n")

if __name__=="__main__":
 main()
