#!/usr/bin/env python3
"""Hungarian assignment audit for CyberTiel QKV row-norm mappings."""
from __future__ import annotations
import argparse,json,math
from pathlib import Path
import numpy as np
from scipy.optimize import linear_sum_assignment

def pearson(a,b):
 a=np.asarray(a,dtype=np.float64); b=np.asarray(b,dtype=np.float64)
 if a.size<2:return 0.0
 a=a-a.mean(); b=b-b.mean()
 denom=math.sqrt(float(np.dot(a,a))*float(np.dot(b,b)))
 return float(np.dot(a,b)/denom) if denom else 0.0

def audit(label, left, right):
 left=np.asarray(left,dtype=np.float64); right=np.asarray(right,dtype=np.float64)
 cost=np.abs(left[:,None]-right[None,:])
 rows,cols=linear_sum_assignment(cost)
 matched_left=left[rows]; matched_right=right[cols]
 abs_diff=np.abs(matched_left-matched_right)
 rel_den=np.maximum(np.maximum(np.abs(matched_left),np.abs(matched_right)),1e-12)
 return {
  'leftSegment':label[0],'rightSegment':label[1],'rowCount':int(left.size),
  'assignmentCostMean':float(cost[rows,cols].mean()),
  'assignmentCostMax':float(cost[rows,cols].max()),
  'matchedNormMeanAbsDiff':float(abs_diff.mean()),
  'matchedNormMaxAbsDiff':float(abs_diff.max()),
  'matchedNormRelativeMean':float((abs_diff/rel_den).mean()),
  'matchedNormRelativeMax':float((abs_diff/rel_den).max()),
  'matchedPearson':pearson(matched_left,matched_right),
  'unmatchedLeftNormPearson':pearson(left,np.sort(right)),
  'assignment':[[int(r),int(c),float(left[r]),float(right[c])] for r,c in zip(rows,cols)],
 }

def main():
 parser=argparse.ArgumentParser(); parser.add_argument('--norms',required=True); parser.add_argument('--output',required=True)
 args=parser.parse_args(); data=json.loads(Path(args.norms).read_text())
 labels=['q2048','k2048','v4096']; records=[]
 for index,label in enumerate(labels):
  audit_result=audit((label,label),data['ggufBlockNorms'][index],data['mlxBlockNorms'][index])
  audit_result.pop('assignment',None); records.append(audit_result)
 cross=[]
 for left_index,left_label in enumerate(labels):
  for right_index,right_label in enumerate(labels):
   if left_index==right_index:continue
   left_length=len(data['ggufBlockNorms'][left_index]); right_length=len(data['mlxBlockNorms'][right_index])
   if left_length!=right_length:
    cross.append({'leftSegment':left_label,'rightSegment':right_label,'skipped':'FEATURE_LENGTH_MISMATCH'});continue
   result_item=audit((left_label,right_label),data['ggufBlockNorms'][left_index],data['mlxBlockNorms'][right_index])
   result_item.pop('assignment',None); cross.append(result_item)
 same=[x for x in records]
 gate={
  'sameSegmentMeanCostAllBelow01':all(x['assignmentCostMean']<0.1 for x in same),
  'sameSegmentRelativeMeanAllBelow025':all(x['matchedNormRelativeMean']<0.25 for x in same),
  'sameSegmentMatchedPearsonAllAbove050':all(x['matchedPearson']>0.5 for x in same),
 }
 result={
  'status':'PASS_WITH_BOUNDARY' if all(gate.values()) else 'FAIL_WITH_BOUNDARY',
  'protocolVersion':'LAB.NAMED_SOURCE.QKV.ROW.ASSIGNMENT.AUDIT.V1',
  'boundary':'ROW_NORM_ASSIGNMENT_ONLY / DOES_NOT_ESTABLISH_FULL_ELEMENT_MAPPING / NO_QUANTIZER_DRIFT_CLAIM',
  'sameSegmentAssignments':same,'crossSegmentAssignments':cross,'gate':gate,
  'interpretation':(
   'ROW_NORM_ASSIGNMENT_SUPPORTS_PERMUTATION_HYPOTHESIS'
   if gate['sameSegmentMatchedPearsonAllAbove050'] and gate['sameSegmentRelativeMeanAllBelow025']
   else 'ROW_NORM_ASSIGNMENT_DOES_NOT_RESOLVE_LAYOUT'
  ),
  'overallPass':all(gate.values()),
 }
 Path(args.output).write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n')

if __name__=='__main__':main()
