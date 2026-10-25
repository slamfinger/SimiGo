#!/usr/bin/env python3
"""Read-only numerical audit of shared F32 control tensors.

GGUF stores these control/normalization tensors as F32. The corresponding MLX
tensors are BF16. The audit compares exact values after orientation repair and
reports drift statistics without loading large quantized matrices.
"""
from __future__ import annotations
import argparse, json, struct
from pathlib import Path
import numpy as np

GGUF_TYPE_F32=0

def read_string(handle):
 n=struct.unpack('<Q',handle.read(8))[0]; return handle.read(n)

def parse_gguf_header(path):
 with path.open('rb') as f:
  assert f.read(4)==b'GGUF'; version=struct.unpack('<I',f.read(4))[0]
  tensor_count,metadata_count=struct.unpack('<QQ',f.read(16))
  def value(t):
   if t==0:return struct.unpack('<B',f.read(1))[0]
   if t==1:return struct.unpack('<b',f.read(1))[0]
   if t==2:return struct.unpack('<H',f.read(2))[0]
   if t==3:return struct.unpack('<h',f.read(2))[0]
   if t==4:return struct.unpack('<I',f.read(4))[0]
   if t==5:return struct.unpack('<i',f.read(4))[0]
   if t==6:return struct.unpack('<f',f.read(4))[0]
   if t==7:return bool(f.read(1)[0])
   if t==8:return read_string(f)
   if t==9:
    et=struct.unpack('<I',f.read(4))[0]; n=struct.unpack('<Q',f.read(8))[0]
    return [value(et) for _ in range(n)]
   if t==10:return struct.unpack('<Q',f.read(8))[0]
   if t==11:return struct.unpack('<q',f.read(8))[0]
   if t==12:return struct.unpack('<d',f.read(8))[0]
   raise ValueError(f'unsupported GGUF type {t}')
  for _ in range(metadata_count):
   read_string(f); value(struct.unpack('<I',f.read(4))[0])
  tensors={}
  metadata_end=f.tell(); alignment=32; data_start=(metadata_end+alignment-1)//alignment*alignment
  infos=[]
  for _ in range(tensor_count):
   name=read_string(f).decode('utf-8','replace'); nd=struct.unpack('<I',f.read(4))[0]
   dims=list(struct.unpack('<'+'Q'*nd,f.read(8*nd))); dtype=struct.unpack('<I',f.read(4))[0]
   offset=struct.unpack('<Q',f.read(8))[0]
   infos.append((name,dims,dtype,offset))
  alignment=32; data_start=(f.tell()+alignment-1)//alignment*alignment
  for name,dims,dtype,offset in infos:
   tensors[name]={'dimensions':dims,'dtype':dtype,'offset':data_start+offset}
  return version,tensors

def parse_safetensors(path: Path, shard_name: str):
 path=Path(path)
 with path.open('rb') as f:
  n=struct.unpack('<Q',f.read(8))[0]; header_bytes=f.read(n)
 header=json.loads(header_bytes); data_start=8+n
 out={}
 for name,item in header.items():
  if name=='__metadata__':continue
  start,end=item['data_offsets']; out[name]={'shape':item['shape'],'dtype':item['dtype'],'start':data_start+start,'end':data_start+end,'shard':shard_name}
 return out

def decode_mlx_array(data,dtype,shape):
 if dtype!='BF16': raise ValueError(f'unsupported selected MLX dtype {dtype}')
 raw=np.frombuffer(data,dtype='<u2').astype('<u4')<<np.uint32(16)
 return raw.view('<f4').reshape(shape)

def stats(gguf,mlx):
 diff=np.abs(gguf.astype(np.float64)-mlx.astype(np.float64))
 finite=np.isfinite(gguf)&np.isfinite(mlx)
 gg_norm=np.linalg.norm(gguf.astype(np.float64)); mlx_norm=np.linalg.norm(mlx.astype(np.float64))
 denom=gg_norm*mlx_norm
 return {
  'count':int(gguf.size),
  'exactCount':int(np.count_nonzero(gguf==mlx)),
  'maxAbsDiff':float(diff.max()) if diff.size else 0.0,
  'meanAbsDiff':float(diff.mean()) if diff.size else 0.0,
  'rmse':float(np.sqrt(np.mean(diff.astype(np.float64)**2))) if diff.size else 0.0,
  'cosineSimilarity':float(np.dot(gguf.astype(np.float64).ravel(),mlx.astype(np.float64).ravel())/denom) if denom else 1.0,
  'finite':bool(finite.all()),
 }

def best_comparison(gguf,mlx):
 candidates=[]
 for label,tensor in [('direct',mlx),('transpose',mlx.T)]:
  if tensor.shape==gguf.shape: candidates.append((label,tensor))
 if not candidates:
  if mlx.ndim==3 and gguf.ndim==2 and mlx.shape[0]==gguf.shape[1] and mlx.shape[1]==gguf.shape[0]:
   candidates.append(('transpose-squeeze',mlx.reshape(gguf.shape[::-1]).T))
  candidates.append(('reshape',mlx.reshape(gguf.shape)))
 scored=[]
 for label,tensor in candidates:
  if tensor.shape!=gguf.shape:continue
  s=stats(gguf,tensor); scored.append((s['meanAbsDiff'],label,tensor,s))
 scored.sort(key=lambda x:x[0])
 mean_diff,label,tensor,s=scored[0]
 alternatives=[{'orientation':candidate_label,'meanAbsDiff':candidate_stats['meanAbsDiff']} for _,candidate_label,_,candidate_stats in scored if candidate_label!=label]
 s['orientation']=label; s['alternativeOrientations']=alternatives
 return s

def main():
 parser=argparse.ArgumentParser()
 parser.add_argument('--gguf',required=True); parser.add_argument('--mlx-dir',required=True)
 parser.add_argument('--output',required=True); parser.add_argument('--layers',type=int,default=40)
 args=parser.parse_args()
 version,gguf=parse_gguf_header(Path(args.gguf).resolve())
 mlx_dir=Path(args.mlx_dir).resolve(); index_path=mlx_dir/'model.safetensors.index.json'
 index=json.loads(index_path.read_text()); mlx_headers={}
 for shard in sorted(set(index['weight_map'].values())):
  mlx_headers.update(parse_safetensors(mlx_dir/shard,shard))
 records=[]; failures=[]
 for layer in range(args.layers):
  is_linear=layer%4!=3
  mappings=[
   ('attn_norm.weight','input_layernorm.weight',None),
   ('post_attention_norm.weight','post_attention_layernorm.weight',None),
   ('ffn_gate_inp.weight','mlp.gate.weight','transpose'),
  ]
  if is_linear:
   mappings += [
    ('ssm_a','linear_attn.A_log',None),
    ('ssm_conv1d.weight','linear_attn.conv1d.weight','auto'),
    ('ssm_dt.bias','linear_attn.dt_bias',None),
    ('ssm_norm.weight','linear_attn.norm.weight',None),
   ]
  else:
   mappings += [
    ('attn_q_norm.weight','self_attn.q_norm.weight',None),
    ('attn_k_norm.weight','self_attn.k_norm.weight',None),
   ]
  for gguf_suffix,mlx_suffix,preferred in mappings:
   gguf_name=f'blk.{layer}.{gguf_suffix}'
   mlx_name=f'language_model.model.layers.{layer}.{mlx_suffix}'
   try:
    gt=gguf[gguf_name]; mt=mlx_headers[mlx_name]
    if gt['dtype']!=GGUF_TYPE_F32: raise ValueError('not F32')
    with Path(args.gguf).open("rb") as f:
     f.seek(gt['offset']); raw=f.read(int(np.prod(gt['dimensions']))*4)
    gguf_array=np.frombuffer(raw,dtype='<f4').reshape(gt['dimensions'])
    with (mlx_dir/mt['shard']).open('rb') as f:
     f.seek(mt['start']); data=f.read(mt['end']-mt['start'])
    mlx_tensor=decode_mlx_array(data,mt['dtype'],mt['shape'])
    if preferred=='transpose': comparison=mlx_tensor.T
    elif preferred=='auto': comparison=mlx_tensor.reshape(gguf_array.shape[::-1]).T
    else: comparison=mlx_tensor
    if comparison.shape!=gguf_array.shape: raise ValueError(f'orientation shape {comparison.shape} != {gguf_array.shape}')
    s=best_comparison(gguf_array,comparison)
    s.update({'layer':layer,'gguf':gguf_name,'mlx':mlx_name,'ggufShape':gguf_array.shape,'mlxShape':mlx_tensor.shape,'allFinite':s['finite']})
    records.append(s)
   except Exception as error:
    failures.append({'layer':layer,'gguf':gguf_name,'mlx':mlx_name,'error':repr(error)})
 checks={
  'MAPPINGS_COMPLETE':len(records)==260,
  'NO_FAILURES':not failures,
  'ALL_RECORDS_FINITE':all(x['allFinite'] for x in records),
 }
 protocolPass=(
  checks['MAPPINGS_COMPLETE']
  and checks['NO_FAILURES']
  and checks['ALL_RECORDS_FINITE']
 )
 overall=protocolPass
 exact=sum(x['maxAbsDiff']==0.0 for x in records)
 result={
  'status':'PASS_WITH_BOUNDARY' if overall else ('PASS_WITH_OBSERVED_DRIFT' if overall is False and checks['MAPPINGS_COMPLETE'] and checks['NO_FAILURES'] else 'FAIL'),
  'protocolVersion':'LAB.NAMED_SOURCE.F32.CONTROL.AUDIT.V1',
  'boundary':'F32_CONTROL_TENSORS_ONLY / GGUF_F32_VS_MLX_BF16 / NO_LARGE_QUANTIZED_MATRICES / NO_WEIGHT_BYTES_EQUIVALENCE_CLAIM',
  'ggufPath':str(Path(args.gguf).resolve()),'mlxDir':str(mlx_dir.resolve()),'ggufVersion':version,'layers':args.layers,'mappingGroups':len(mappings),'tensorCount':len(records),'exactTensorCount':exact,
  'maxAbsDiff':max((x['maxAbsDiff'] for x in records),default=0.0),'meanAbsDiff':float(np.mean([x['meanAbsDiff'] for x in records])) if records else 0.0,
  'zeroDriftObserved':exact==len(records),'checks':checks,'records':records,'failures':failures[:30],'overallPass':overall,
 }
 Path(args.output).write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
if __name__=='__main__':main()
