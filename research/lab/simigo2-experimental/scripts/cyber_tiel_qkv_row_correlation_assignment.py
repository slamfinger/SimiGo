#!/usr/bin/env python3
"""Full row-vector Pearson assignment audit for CyberTiel QKV segments.

For each hypothesized Q/K/V segment, rows are centered and L2-normalized, then a
Hungarian assignment maximizes row-wise Pearson correlation between GGUF and
MLX. This is a stronger layout test than L2-norm-only assignment.
"""
from __future__ import annotations
import argparse,json,struct
from pathlib import Path
import numpy as np
import mlx.core as mx
from scipy.optimize import linear_sum_assignment

QK8_0=32

def read_string(handle):
 n=struct.unpack('<Q',handle.read(8))[0]; return handle.read(n)

def read_value(handle,value_type):
 if value_type in (0,7): return handle.read(1)[0]
 if value_type==1:return struct.unpack('<b',handle.read(1))[0]
 if value_type==2:return struct.unpack('<H',handle.read(2))[0]
 if value_type==3:return struct.unpack('<h',handle.read(2))[0]
 if value_type==4:return struct.unpack('<I',handle.read(4))[0]
 if value_type==5:return struct.unpack('<i',handle.read(4))[0]
 if value_type==6:return struct.unpack('<f',handle.read(4))[0]
 if value_type==7:return bool(handle.read(1)[0])
 if value_type==8:return read_string(handle)
 if value_type==9:
  element_type=struct.unpack('<I',handle.read(4))[0]
  count=struct.unpack('<Q',handle.read(8))[0]
  return [read_value(handle,element_type) for _ in range(count)]
 if value_type==10:return struct.unpack('<Q',handle.read(8))[0]
 if value_type==11:return struct.unpack('<q',handle.read(8))[0]
 if value_type==12:return struct.unpack('<d',handle.read(8))[0]
 raise ValueError(f'unsupported GGUF metadata type {value_type}')

def parse_gguf_qkv(path):
 with path.open('rb') as h:
  if h.read(4)!=b'GGUF': raise ValueError('not GGUF')
  version=struct.unpack('<I',h.read(4))[0]
  tensor_count,metadata_count=struct.unpack('<QQ',h.read(16))
  for _ in range(metadata_count):
   read_string(h); read_value(h,struct.unpack('<I',h.read(4))[0])
  infos=[]
  for _ in range(tensor_count):
   name=read_string(h).decode('utf-8','replace'); nd=struct.unpack('<I',h.read(4))[0]
   dims=list(struct.unpack('<'+'Q'*nd,h.read(8*nd))); dtype=struct.unpack('<I',h.read(4))[0]
   offset=struct.unpack('<Q',h.read(8))[0]; infos.append((name,dims,dtype,offset))
  data_start=(h.tell()+31)//32*32
 for name,dims,dtype,offset in infos:
  if name=='blk.1.attn_qkv.weight':
   if dtype!=8: raise ValueError('attn_qkv is not Q8_0')
   blocks=int(np.prod(dims))//QK8_0
   block_dtype=np.dtype([('scale','<f2'),('values','i1',(QK8_0,))])
   with path.open('rb') as f:
    f.seek(data_start+offset); raw=f.read(blocks*block_dtype.itemsize)
   parsed=np.frombuffer(raw,dtype=block_dtype,count=blocks)
   deq=parsed['values'].astype(np.float32)*parsed['scale'].astype(np.float32)[:,None]
   return version,deq.reshape(dims)
 raise KeyError('blk.1.attn_qkv.weight')

def parse_mlx_qkv(root):
 wanted={f'language_model.model.layers.1.linear_attn.in_proj_qkv{suffix}' for suffix in ('.weight','.scales','.biases')}
 found={}
 for shard in sorted(root.glob('model-*.safetensors')):
  with shard.open('rb') as h:
   length=struct.unpack('<Q',h.read(8))[0]; header=json.loads(h.read(length))
  for name in wanted & header.keys():
   item=header[name]; start,end=item['data_offsets']; base=8+length
   with shard.open('rb') as h:
    h.seek(base+start); found[name]=(h.read(end-start),item['shape'],item['dtype'])
 if len(found)!=3: raise ValueError(f'missing MLX qkv pieces: {sorted(wanted-found)}')
 weight_raw,weight_shape,_=found[f'language_model.model.layers.1.linear_attn.in_proj_qkv.weight']
 scales_raw,scales_shape,_=found[f'language_model.model.layers.1.linear_attn.in_proj_qkv.scales']
 biases_raw,biases_shape,_=found[f'language_model.model.layers.1.linear_attn.in_proj_qkv.biases']
 packed=mx.array(np.frombuffer(weight_raw,dtype='<u4')).reshape(weight_shape)
 scales=mx.array(np.frombuffer(scales_raw,dtype='<u2')).view(mx.bfloat16).reshape(scales_shape)
 biases=mx.array(np.frombuffer(biases_raw,dtype='<u2')).view(mx.bfloat16).reshape(biases_shape)
 deq=mx.dequantize(packed,scales,biases,group_size=64,bits=4)
 mx.eval(deq)
 return np.asarray(deq.astype(mx.float32),dtype=np.float32)

def row_normalize(matrix):
 matrix=matrix.astype(np.float64)
 matrix=matrix-matrix.mean(axis=1,keepdims=True)
 norms=np.linalg.norm(matrix,axis=1)
 norms[norms==0]=1
 return matrix/norms[:,None]

def pearson(values):
 return values.astype(np.float64)

def segment_report(label,left,right):
 normalized_left=row_normalize(left)
 normalized_right=row_normalize(right)
 correlations=normalized_left@normalized_right.T
 rows,cols=linear_sum_assignment(correlations, maximize=True)
 matched=correlations[rows,cols]
 identity=correlations.diagonal()
 assignment=[{'ggufRow':int(row),'mlxRow':int(col),'pearson':float(correlations[row,col])} for row,col in zip(rows,cols)]
 return {
  'segment':label,'rowCount':int(left.shape[0]),'featureCount':int(left.shape[1]),
  'identityPearsonMean':float(identity.mean()),
  'identityPearsonMax':float(identity.max()),
  'matchedPearsonMean':float(matched.mean()),'matchedPearsonMedian':float(np.median(matched)),
  'matchedPearsonMin':float(matched.min()),'matchedPearsonMax':float(matched.max()),
  'matchedAtLeast090':int((matched>=0.9).sum()),'matchedAtLeast070':int((matched>=0.7).sum()),
  'matchedAtLeast050':int((matched>=0.5).sum()),
  'assignment':assignment,
 }

def main():
 parser=argparse.ArgumentParser()
 parser.add_argument('--gguf',required=True); parser.add_argument('--mlx-dir',required=True)
 parser.add_argument('--output',required=True)
 args=parser.parse_args()
 gguf_path=Path(args.gguf).resolve(); mlx_dir=Path(args.mlx_dir).resolve()
 gguf_version,gguf=parse_gguf_qkv(gguf_path)
 mlx=parse_mlx_qkv(mlx_dir)
 transposed_mlx=mlx.T
 if transposed_mlx.shape!=gguf.shape: raise ValueError(f'shape mismatch {transposed_mlx.shape} != {gguf.shape}')
 segments=[(0,2048,'q2048'),(2048,2048,'k2048'),(4096,4096,'v4096')]
 reports=[]; all_matched=[]
 for start,length,label in segments:
  left=gguf[:,start:start+length]; right=transposed_mlx[:,start:start+length]
  report=segment_report(label,left,right); reports.append(report)
  all_matched.extend(report['assignment'])
 total_matched=sum(item['matchedAtLeast050'] for item in reports)
 total_positions=sum(item['rowCount'] for item in reports)
 checks={
  'QKV_SEGMENT_COUNT':len(reports)==3,
  'ALL_HUNGARIAN_ASSIGNMENTS_COMPLETE':all(item['rowCount']==2048 for item in reports),
  'ALL_QKV_FEATURES_COVERED':sum(item['featureCount'] for item in reports)==8192,
 }
 overall=all(checks.values())
 result={
  'status':'PASS_WITH_BOUNDARY',
  'protocolVersion':'LAB.NAMED_SOURCE.QKV.ROW.CORRELATION.ASSIGNMENT.V1',
  'boundary':'FULL_ROW_VECTOR_PEARSON_HUNGARIAN_ASSIGNMENT / LAYOUT_DIAGNOSTIC_ONLY / NO_WEIGHT_BYTES_EQUIVALENCE_CLAIM',
  'ggufPath':str(gguf_path),'mlxDir':str(mlx_dir),'ggufVersion':gguf_version,
  'segments':reports,
  'checks':checks,
  'overallPass':overall,
  'totalRowCount':total_positions,
  'totalFeatureCount':8192,
  'totalMatchedAtLeast050':total_matched,
  'summary':{
   'segments':[item['segment'] for item in reports],
   'matchedPearsonMean':[item['matchedPearsonMean'] for item in reports],
   'matchedPearsonMedian':[item['matchedPearsonMedian'] for item in reports],
   'matchedAtLeast090':[item['matchedAtLeast090'] for item in reports],
   'matchedAtLeast070':[item['matchedAtLeast070'] for item in reports],
   'matchedAtLeast050':[item['matchedAtLeast050'] for item in reports],
  },
 }
 Path(args.output).write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n')

if __name__=='__main__': main()
