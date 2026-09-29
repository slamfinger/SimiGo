#!/usr/bin/env python3
"""Diagnose fused Q/K/V segment ordering for CyberTiel GGUF vs MLX.

Uses row/block norm correlations only. This is a layout diagnostic and does not
establish quantizer drift or checkpoint identity.
"""
from __future__ import annotations
import argparse, itertools, json, math, struct
from pathlib import Path
import numpy as np
import mlx.core as mx

QK8_0=32

def read_string(handle):
 length=struct.unpack('<Q',handle.read(8))[0]; return handle.read(length)

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

def parse_gguf_tensor(path,name):
 with path.open('rb') as handle:
  if handle.read(4)!=b'GGUF': raise ValueError('not GGUF')
  version=struct.unpack('<I',handle.read(4))[0]
  tensor_count,metadata_count=struct.unpack('<QQ',handle.read(16))
  for _ in range(metadata_count):
   read_string(handle)
   read_value(handle,struct.unpack('<I',handle.read(4))[0])
  infos=[]
  for _ in range(tensor_count):
   tensor_name=read_string(handle).decode('utf-8','replace')
   dimension_count=struct.unpack('<I',handle.read(4))[0]
   dimensions=list(struct.unpack('<'+'Q'*dimension_count,handle.read(8*dimension_count)))
   gguf_type=struct.unpack('<I',handle.read(4))[0]
   offset=struct.unpack('<Q',handle.read(8))[0]
   infos.append((tensor_name,dimensions,gguf_type,offset))
  data_start=(handle.tell()+31)//32*32
 for tensor_name,dimensions,gguf_type,offset in infos:
  if tensor_name==name:
   if gguf_type!=8: raise ValueError('not Q8_0')
   blocks=int(np.prod(dimensions))//QK8_0
   block_dtype=np.dtype([('scale','<f2'),('values','i1',(QK8_0,))])
   with path.open('rb') as handle:
    handle.seek(data_start+offset); raw=handle.read(blocks*block_dtype.itemsize)
   parsed=np.frombuffer(raw,dtype=block_dtype,count=blocks)
   dequant=parsed['values'].astype(np.float32)*parsed['scale'].astype(np.float32)[:,None]
   return dequant.reshape(dimensions)
 raise KeyError(name)

def parse_mlx_tensor(root,name,group_size,bits):
 pieces={}; found_header=None
 for shard in sorted(root.glob('model-*.safetensors')):
  with shard.open('rb') as handle:
   header_length=struct.unpack('<Q',handle.read(8))[0]
   header=json.loads(handle.read(header_length))
  for suffix in ('.weight','.scales','.biases'):
   key=name+suffix
   if key in header:
    found_header=header
    item=header[key]; start,end=item['data_offsets']; base=8+header_length
    with shard.open('rb') as handle:
     handle.seek(base+start); pieces[suffix]=handle.read(end-start)
 if len(pieces)!=3:
  print('DEBUG PIECES',pieces.keys())
  raise ValueError(f'missing MLX pieces for {name}: {sorted(pieces)}')
 packed_shape=found_header[name+'.weight']['shape']
 scale_shape=found_header[name+'.scales']['shape']; bias_shape=found_header[name+'.biases']['shape']
 packed=mx.array(np.frombuffer(pieces['.weight'],dtype='<u4')).reshape(packed_shape)
 scales=mx.array(np.frombuffer(pieces['.scales'],dtype='<u2')).view(mx.bfloat16).reshape(scale_shape)
 biases=mx.array(np.frombuffer(pieces['.biases'],dtype='<u2')).view(mx.bfloat16).reshape(bias_shape)
 dequantized=mx.dequantize(packed,scales,biases,group_size=group_size,bits=bits)
 mx.eval(dequantized)
 return np.asarray(dequantized.astype(mx.float32),dtype=np.float32)

def pearson(left,right):
 left=np.asarray(left,dtype=np.float64); right=np.asarray(right,dtype=np.float64)
 if left.size<2 or right.size<2 or left.size!=right.size:return 0.0
 left=left-left.mean(); right=right-right.mean()
 denominator=math.sqrt(float(np.dot(left,left))*float(np.dot(right,right)))
 return float(np.dot(left,right)/denominator) if denominator else 0.0

def pearson_matrix(left,right):
 left=left.astype(np.float64); right=right.astype(np.float64)
 left=left-left.mean(axis=1,keepdims=True)
 right=right-right.mean(axis=1,keepdims=True)
 left_norms=np.linalg.norm(left,axis=1); right_norms=np.linalg.norm(right,axis=1)
 left_norms[left_norms==0]=1; right_norms[right_norms==0]=1
 return (left/left_norms[:,None])@(right/right_norms[:,None]).T

def main():
 parser=argparse.ArgumentParser()
 parser.add_argument('--gguf',required=True); parser.add_argument('--mlx-dir',required=True)
 parser.add_argument('--layer',type=int,default=1); parser.add_argument('--output',required=True); parser.add_argument('--debug-norms')
 args=parser.parse_args()
 gguf_path=Path(args.gguf).resolve(); mlx_dir=Path(args.mlx_dir).resolve()
 gguf_name=f'blk.{args.layer}.attn_qkv.weight'
 mlx_name=f'language_model.model.layers.{args.layer}.linear_attn.in_proj_qkv'
 config=json.loads((mlx_dir/'config.json').read_text())['quantization']
 group_size=int(config.get('group_size',64)); bits=int(config.get('bits',4))
 gguf=parse_gguf_tensor(gguf_path,gguf_name)
 mlx=parse_mlx_tensor(mlx_dir,mlx_name,group_size,bits)
 transposed_mlx=mlx.T
 if transposed_mlx.shape!=gguf.shape: raise ValueError(f'shape mismatch {transposed_mlx.shape} != {gguf.shape}')
 segments=[(0,2048,'q2048'),(2048,2048,'k2048'),(4096,4096,'v4096')]
 gguf_block_norms=[]
 mlx_block_norms=[]
 for start,length,label in segments:
  gguf_norms=np.linalg.norm(gguf[:,start:start+length],axis=1)
  mlx_norms=np.linalg.norm(transposed_mlx[:,start:start+length],axis=1)
  gguf_block_norms.append(gguf_norms); mlx_block_norms.append(mlx_norms)
 correlations={}
 for left_index,(left_start,left_length,left_label) in enumerate(segments):
  for right_index,(right_start,right_length,right_label) in enumerate(segments):
   correlations[f'{left_label}_vs_{right_label}']=pearson(gguf_block_norms[left_index],mlx_block_norms[right_index])
 permutations=[]
 for permutation in itertools.permutations(range(3)):
  concatenated_mlx=np.concatenate([mlx_block_norms[index] for index in permutation])
  concatenated_gguf=np.concatenate(gguf_block_norms)
  permutations.append({'permutation':[segments[index][2] for index in permutation],'indices':list(permutation),'pearson':pearson(concatenated_gguf,concatenated_mlx)})
 permutations.sort(key=lambda item:item['pearson'],reverse=True)
 row_assignments=[]
 for left_index,(left_start,left_length,left_label) in enumerate(segments):
  for right_index,(right_start,right_length,right_label) in enumerate(segments):
   if left_length!=right_length:
    row_assignments.append({
     'ggufSegment':left_label,'mlxSegment':right_label,'rowCount':0,
     'bestPearsonMean':None,'bestPearsonMedian':None,'bestPearsonMax':None,
     'countAtLeast050':None,'countAtLeast080':None,'skipped':'FEATURE_LENGTH_MISMATCH',
    })
    continue
   matrix=pearson_matrix(gguf[:,left_start:left_start+left_length],transposed_mlx[:,right_start:right_start+right_length])
   best=matrix.max(axis=1)
   row_assignments.append({
    'ggufSegment':left_label,'mlxSegment':right_label,'rowCount':int(best.size),
    'bestPearsonMean':float(best.mean()),'bestPearsonMedian':float(np.median(best)),
    'bestPearsonMax':float(best.max()),'countAtLeast050':int((best>=0.5).sum()),
    'countAtLeast080':int((best>=0.8).sum()),
   })
 natural_correlation=correlations['q2048_vs_q2048']+correlations['k2048_vs_k2048']+correlations['v4096_vs_v4096']
 best_permutation=permutations[0]
 result={
  'status':'PASS_WITH_BOUNDARY' if all(abs(value)<0.2 for value in correlations.values()) else 'PASS_WITH_BOUNDARY',
  'protocolVersion':'LAB.NAMED_SOURCE.QKV.SEGMENT.DIAGNOSTIC.V1',
  'boundary':'ROW_BLOCK_NORM_AND_ROW_CORRELATION_DIAGNOSTIC / LAYOUT_NOT_RESOLVED / NO_QUANTIZER_DRIFT_CLAIM',
  'ggufPath':str(gguf_path),'mlxPath':str(mlx_dir),'layer':args.layer,
  'ggufTensor':gguf_name,'mlxTensor':mlx_name,
  'mlxQuantization':{'groupSize':group_size,'bits':bits},
  'segmentHypothesis':[{'name':label,'start':start,'length':length} for start,length,label in segments],
  'blockNormCorrelations':correlations,
  'naturalOrderSummedPearson':natural_correlation,
  'segmentPermutationsRanked':permutations,
  'bestPermutation':best_permutation,
  'layoutResolved':False,
  'interpretation':'BEST_SEGMENT_ORDER_SUGGESTIVE_BUT_ROW_MAPPING_ABSENT / LAYOUT_UNRESOLVED',
  'rowAssignments':row_assignments,
 }
 Path(args.output).write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True,default=lambda x:x.tolist() if isinstance(x,np.ndarray) else str(x))+'\n')
 if args.debug_norms:
  Path(args.debug_norms).write_text(json.dumps({'ggufBlockNorms':[x.tolist() for x in gguf_block_norms],'mlxBlockNorms':[x.tolist() for x in mlx_block_norms]},ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__': main()
