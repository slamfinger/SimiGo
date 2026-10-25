#!/usr/bin/env python3
"""Read-only quantized-tensor drift pilot for CyberTiel GGUF vs MLX.

Compares three layer-1 Q8_0 GGUF tensors with mapped MLX affine-quantized
tensors after full dequantization. Formats differ, so the result is an
observed drift boundary, not a same-checkpoint proof.
"""
from __future__ import annotations
import argparse, heapq, json, math, struct
from pathlib import Path
import numpy as np
import mlx.core as mx

GGUF_Q8_0=8
QK8_0=32

def read_string(handle):
 length=struct.unpack('<Q',handle.read(8))[0]
 return handle.read(length)

def read_value(handle,value_type):
 if value_type in (0,7): return handle.read(1)[0]
 if value_type==1:return struct.unpack('<b',handle.read(1))[0]
 if value_type==2:return struct.unpack('<H',handle.read(2))[0]
 if value_type==3:return struct.unpack('<h',handle.read(2))[0]
 if value_type==4:return struct.unpack('<I',handle.read(4))[0]
 if value_type==5:return struct.unpack('<i',handle.read(4))[0]
 if value_type==6:return struct.unpack('<f',handle.read(4))[0]
 if value_type==8:return read_string(handle)
 if value_type==9:
  element_type=struct.unpack('<I',handle.read(4))[0]
  count=struct.unpack('<Q',handle.read(8))[0]
  return [read_value(handle,element_type) for _ in range(count)]
 if value_type==10:return struct.unpack('<Q',handle.read(8))[0]
 if value_type==11:return struct.unpack('<q',handle.read(8))[0]
 if value_type==12:return struct.unpack('<d',handle.read(8))[0]
 raise ValueError(f'unsupported GGUF metadata type {value_type}')

def parse_gguf_selected(path,selected):
 with path.open('rb') as handle:
  if handle.read(4)!=b'GGUF': raise ValueError('not GGUF')
  version=struct.unpack('<I',handle.read(4))[0]
  tensor_count,metadata_count=struct.unpack('<QQ',handle.read(16))
  for _ in range(metadata_count):
   read_string(handle)
   value_type=struct.unpack('<I',handle.read(4))[0]
   read_value(handle,value_type)
  infos=[]
  for _ in range(tensor_count):
   name=read_string(handle).decode('utf-8','replace')
   dimension_count=struct.unpack('<I',handle.read(4))[0]
   dimensions=list(struct.unpack('<'+'Q'*dimension_count,handle.read(8*dimension_count)))
   gguf_type=struct.unpack('<I',handle.read(4))[0]
   offset=struct.unpack('<Q',handle.read(8))[0]
   infos.append((name,dimensions,gguf_type,offset))
  data_start=(handle.tell()+31)//32*32
 tensors={}
 for name,dimensions,gguf_type,offset in infos:
  if name in selected: tensors[name]={'dimensions':dimensions,'ggufType':gguf_type,'dataOffset':data_start+offset}
 return version,tensors

def dequantize_q8_0(path,tensor):
 dimensions=tensor['dimensions']
 element_count=int(np.prod(dimensions))
 if element_count%QK8_0: raise ValueError('Q8_0 element count is not divisible by 32')
 blocks=element_count//QK8_0
 block_dtype=np.dtype([('scale','<f2'),('values','i1',(QK8_0,))])
 with path.open('rb') as handle:
  handle.seek(tensor['dataOffset']); raw=handle.read(blocks*block_dtype.itemsize)
 if len(raw)!=blocks*block_dtype.itemsize: raise ValueError('short Q8_0 read')
 parsed=np.frombuffer(raw,dtype=block_dtype,count=blocks)
 dequant=parsed['values'].astype(np.float32)*parsed['scale'].astype(np.float32)[:,None]
 return dequant.reshape(dimensions)

def parse_safetensors(mlx_dir,logical_names):
 wanted={name+suffix for name in logical_names for suffix in ('.weight','.scales','.biases')}
 entries={}
 for shard_path in sorted(mlx_dir.glob('model-*.safetensors')):
  with shard_path.open('rb') as handle:
   header_length=struct.unpack('<Q',handle.read(8))[0]
   header=json.loads(handle.read(header_length))
  for name in wanted:
   if name not in header: continue
   item=header[name]; start,end=item['data_offsets']; data_start=8+header_length
   entries[name]={'shardPath':str(shard_path),'start':data_start+start,'end':data_start+end,'shape':item['shape'],'dtype':item['dtype']}
 missing={name+suffix for name in logical_names for suffix in ('.weight','.scales','.biases')}-set(entries)
 if missing: raise ValueError(f'MLX tensors not found in shards: {sorted(missing)}')
 return entries

def read_bytes(entry):
 with Path(entry['shardPath']).open('rb') as handle:
  handle.seek(entry['start']); return handle.read(entry['end']-entry['start'])

def mlx_bf16(data,shape):
 return mx.array(np.frombuffer(data,dtype='<u2')).view(mx.bfloat16).reshape(shape)

def mlx_u32(data,shape):
 return mx.array(np.frombuffer(data,dtype='<u4')).reshape(shape)

def mlx_to_numpy(array):
 return np.asarray(array.astype(mx.float32),dtype=np.float32)

def pearson(left,right):
 left=np.asarray(left,dtype=np.float64); right=np.asarray(right,dtype=np.float64)
 if left.size<2:return 0.0
 left=left-left.mean(); right=right-right.mean()
 denominator=math.sqrt(float(np.dot(left,left))*float(np.dot(right,right)))
 return float(np.dot(left,right)/denominator) if denominator else 0.0

def stats(gguf,mlx):
 if gguf.shape!=mlx.shape: raise ValueError(f'shape mismatch {gguf.shape} != {mlx.shape}')
 flat_gguf=gguf.reshape(-1); flat_mlx=mlx.reshape(-1)
 total=flat_gguf.size
 abs_sum=0.0; max_abs=0.0; max_index=0
 dot=0.0; gguf_sq=0.0; mlx_sq=0.0; exact=0; finite=True
 thresholds=[0.001,0.0025,0.005,0.01,0.025,0.05,0.1,0.25,0.5,1.0,2.5]
 histogram=[0]*len(thresholds)
 top=[]
 for start in range(0,total,1_000_000):
  end=min(total,start+1_000_000)
  left=flat_gguf[start:end]; right=flat_mlx[start:end]
  finite_mask=np.isfinite(left)&np.isfinite(right)
  finite=finite and bool(finite_mask.all())
  left=left[finite_mask]; right=right[finite_mask]
  delta=np.abs(left-right)
  abs_sum+=float(delta.sum(dtype=np.float64))
  local_index=int(delta.argmax()); local_max=float(delta[local_index])
  if local_max>max_abs:
   max_abs=local_max; max_index=start+local_index
  dot+=float(np.dot(left.astype(np.float64),right.astype(np.float64)))
  gguf_sq+=float(np.dot(left.astype(np.float64),left.astype(np.float64)))
  mlx_sq+=float(np.dot(right.astype(np.float64),right.astype(np.float64)))
  exact+=int(np.count_nonzero(left==right))
  buckets=np.searchsorted(thresholds,delta,side='right')
  for bucket in buckets: histogram[int(bucket)]+=1
  for local_offset in np.argpartition(delta,-min(10,delta.size))[-min(10,delta.size):]:
   absolute=float(delta[local_offset])
   item=(-absolute,start+int(local_offset),float(left[local_offset]),float(right[local_offset]))
   if len(top)<10: heapq.heappush(top,item)
   elif item>top[0]: heapq.heapreplace(top,item)
 denominator=math.sqrt(gguf_sq*mlx_sq)
 cosine=dot/denominator if denominator else 1.0
 numerator=total*dot-flat_gguf.sum(dtype=np.float64)*flat_mlx.sum(dtype=np.float64)
 variance_left=total*gguf_sq-flat_gguf.sum(dtype=np.float64)**2
 variance_right=total*mlx_sq-flat_mlx.sum(dtype=np.float64)**2
 pearson=numerator/math.sqrt(variance_left*variance_right) if variance_left>0 and variance_right>0 else 0.0
 top_samples=[{'flatIndex':-item[0],'absDiff':-item[0] and -item[0] or 0.0,'gguf':item[1],'mlx':item[2]} for item in sorted(top,reverse=True)]
 # Replace placeholder flatIndex values from stored heap tuples.
 top_samples=[]
 for negative_absolute,index,left,right in sorted(top):
  top_samples.append({'flatIndex':index,'absDiff':-negative_absolute,'gguf':left,'mlx':right})
 return {
  'count':int(total),'finite':finite,'exactCount':exact,
  'maxAbsDiff':max_abs,'meanAbsDiff':abs_sum/total,
  'cosineSimilarity':cosine,'pearsonCorrelation':pearson,
  'absHistogramThresholds':thresholds,
  'absHistogramCountsGreaterOrEqual':histogram,
  'topDifferences':top_samples,
 }

def main():
 parser=argparse.ArgumentParser()
 parser.add_argument('--gguf',required=True)
 parser.add_argument('--mlx-dir',required=True)
 parser.add_argument('--output',required=True)
 parser.add_argument('--layer',type=int,default=1)
 args=parser.parse_args()
 gguf_path=Path(args.gguf).resolve(); mlx_dir=Path(args.mlx_dir).resolve()
 index_path=mlx_dir/'model.safetensors.index.json'
 selected=[
  {'gguf':f'blk.{args.layer}.attn_qkv.weight','mlx':f'language_model.model.layers.{args.layer}.linear_attn.in_proj_qkv','family':'linear_attn_qkv'},
  {'gguf':f'blk.{args.layer}.attn_gate.weight','mlx':f'language_model.model.layers.{args.layer}.linear_attn.in_proj_z','family':'linear_attn_gate'},
  {'gguf':f'blk.{args.layer}.ssm_out.weight','mlx':f'language_model.model.layers.{args.layer}.linear_attn.out_proj','family':'linear_attn_out'},
 ]
 version,gguf=parse_gguf_selected(gguf_path,{item['gguf'] for item in selected})
 entries=parse_safetensors(mlx_dir,{item['mlx'] for item in selected})
 quantization=json.loads((mlx_dir/'config.json').read_text())['quantization']
 records=[]
 for item in selected:
  gguf_name=item['gguf']; mlx_name=item['mlx']; family=item['family']
  gguf_tensor=gguf[gguf_name]
  if gguf_tensor['ggufType']!=GGUF_Q8_0: raise ValueError(f'{gguf_name} is not Q8_0')
  config=quantization.get(mlx_name) or {
   'groupSize':quantization['group_size'],'bits':quantization['bits'],'mode':quantization['mode']
  }
  gguf_dequantized=dequantize_q8_0(gguf_path,gguf_tensor)
  weight_entry=entries[mlx_name+'.weight']
  weight_data=read_bytes(weight_entry)
  scales_name=mlx_name+'.scales'; biases_name=mlx_name+'.biases'
  scale_entry=entries[scales_name]; bias_entry=entries[biases_name]
  scales_data=read_bytes(scale_entry); biases_data=read_bytes(bias_entry)
  group_size=config.get('groupSize',config.get('group_size',64))
  bits=config.get('bits',4)
  mode=config.get('mode','affine')
  mlx_dequantized_mx=mx.dequantize(
   mlx_u32(weight_data,weight_entry['shape']),
   mlx_bf16(scales_data,scale_entry['shape']),
   mlx_bf16(biases_data,bias_entry['shape']),
   group_size=int(group_size),bits=int(bits),mode=mode
  )
  mx.eval(mlx_dequantized_mx)
  mlx_dequantized=mlx_to_numpy(mlx_dequantized_mx)
  comparison=mlx_dequantized.T
  if comparison.shape!=gguf_dequantized.shape:
   raise ValueError(f'mapped shape mismatch {comparison.shape} != {gguf_dequantized.shape}')
  gguf_two_d=gguf_dequantized
  mlx_two_d=mlx_dequantized
  gguf_row_norms=np.linalg.norm(gguf_two_d,axis=1)
  gguf_column_norms=np.linalg.norm(gguf_two_d,axis=0)
  mlx_row_norms=np.linalg.norm(mlx_two_d,axis=1)
  mlx_column_norms=np.linalg.norm(mlx_two_d,axis=0)
  diagnostics={
   'transposeRowNormPearson':pearson(gguf_row_norms,mlx_column_norms),
   'transposeColumnNormPearson':pearson(gguf_column_norms,mlx_row_norms),
   'transposeSortedRowNormPearson':pearson(np.sort(gguf_row_norms),np.sort(mlx_column_norms)),
   'transposeSortedColumnNormPearson':pearson(np.sort(gguf_column_norms),np.sort(mlx_row_norms)),
  }
  statistics=stats(gguf_dequantized,comparison)
  records.append({
   'gguf':gguf_name,'mlx':mlx_name,'family':family,
   'ggufFormat':'Q8_0','ggufDimensions':gguf_tensor['dimensions'],
   'mlxQuantization':{'groupSize':int(group_size),'bits':int(bits),'mode':mode},
   'mlxPhysicalShapes':{key:weight_entry.get('shape') for key,weight_entry in [('weight',weight_entry),('scales',scale_entry),('biases',bias_entry)]},
   'mlxLogicalShape':weight_entry['shape'],
   'orientation':'GGUF transpose ↔ MLX dequantized',
   **statistics,
   **diagnostics,
  })
 all_finite=all(record['finite'] for record in records)
 protocol_pass=len(records)==len(selected) and all_finite
 result={
  'status':'PASS_WITH_BOUNDARY' if protocol_pass else 'FAIL',
  'layoutResolved':False,
  'elementwiseCorrelationNearZero':all(abs(record['cosineSimilarity'])<0.01 for record in records),
  'interpretation':'LAYOUT_OR_SOURCE_MISMATCH_UNRESOLVED / QUANTIZER_DRIFT_NOT_ATTRIBUTABLE',
  'protocolVersion':'LAB.NAMED_SOURCE.QUANTIZED.DRIFT.PILOT.V1',
  'boundary':'THREE_Q8_0_VS_MLX_AFFINE_TENSORS / FULL_DEQUANT / NO_WEIGHT_BYTES_EQUIVALENCE_CLAIM',
  'layer':args.layer,'tensorCount':len(records),'allFinite':all_finite,
  'exactTensorCount':sum(record['exactCount']==record['count'] for record in records),
  'zeroDriftTensorCount':sum(record['maxAbsDiff']==0.0 for record in records),
  'overallPass':protocol_pass,
  'quantizationFormats':{
   'gguf':'Q8_0 block scale + int8',
   'mlx':'affine scales/biases with per-tensor group size and bits',
  },
  'records':records,
  'nonClaims':[
   'same checkpoint bytes','same quantization grid','dequantization equivalence',
   'tensor element mapping established','quantizer drift established',
   'full model drift characterization','MTP mechanism explanation',
  ],
 }
 Path(args.output).write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n')

if __name__=='__main__': main()
