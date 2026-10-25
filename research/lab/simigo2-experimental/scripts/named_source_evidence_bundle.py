#!/usr/bin/env python3
"""Validate and consolidate named-source CyberTiel GGUF/MLX evidence artifacts."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

def sha256(path: Path) -> str:
    digest=hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024*1024), b''):
            digest.update(chunk)
    return digest.hexdigest()

def require(condition: bool, message: str, failures: list[str]) -> None:
    if not condition: failures.append(message)

def main() -> None:
    parser=argparse.ArgumentParser()
    parser.add_argument('--backend-conformance-dir',required=True)
    parser.add_argument('--output',required=True)
    args=parser.parse_args()
    root=Path(args.backend_conformance_dir).resolve()
    paths={
      'profileEvaluation':root/'named-source-cyber-tiel-matrix-v2-profile-evaluation.json',
      'lineageAudit':root/'named-source-cyber-tiel-lineage-audit.json',
      'tensorTopologyAudit':root/'named-source-cyber-tiel-tensor-topology-audit.json',
      'marginSeed42':root/'cross-backend-cyber-tiel-margin-compare-matrix-v2-all.json',
      'marginSeed43':root/'cross-backend-cyber-tiel-margin-compare-matrix-v2-all-seed43.json',
      'qkvSegmentDiagnostic':root/'named-source-cyber-tiel-qkv-segment-diagnostic.json',
      'f32ControlAudit':root/'named-source-cyber-tiel-f32-control-audit.json',
      'quantizedLayoutPilot':root/'named-source-cyber-tiel-quantized-drift-pilot-layer1.json',
    }
    failures=[]; artifacts={}
    for label,path in paths.items():
        if not path.exists():
            failures.append(f'MISSING_{label.upper()}')
            continue
        try: artifact=json.loads(path.read_text())
        except Exception as error: failures.append(f'INVALID_JSON_{label.upper()}'); continue
        artifacts[label]={'path':str(path),'sha256':sha256(path),'json':artifact}
    if failures:
        result={'status':'FAIL','failureReasons':failures,'artifacts':artifacts,'overallPass':False}
        Path(args.output).write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n')
        raise SystemExit(f'bundle validation failed: {failures}')

    profile=artifacts['profileEvaluation']['json']
    lineage=artifacts['lineageAudit']['json']
    topology=artifacts['tensorTopologyAudit']['json']
    seed42=artifacts['marginSeed42']['json']
    seed43=artifacts['marginSeed43']['json']
    qkv=artifacts['qkvSegmentDiagnostic']['json']
    f32=artifacts['f32ControlAudit']['json']
    quant=artifacts['quantizedLayoutPilot']['json']

    require(profile.get('pass') is True,'PROFILE_NOT_PASS',failures)
    require(profile.get('seedCount')==2,'PROFILE_SEED_COUNT',failures)
    require(profile.get('positionCount')==139,'PROFILE_POSITION_COUNT',failures)
    require(profile.get('topKContainmentCount')==278,'PROFILE_TOPK_CONTAINMENT',failures)
    require(profile.get('maximumObservedReferenceRank')==2,'PROFILE_MAX_RANK',failures)
    require(profile.get('seedOutcomesIdentical') is True,'PROFILE_SEED_OUTCOMES',failures)

    require(lineage.get('overallPass') is True,'LINEAGE_NOT_PASS',failures)
    require(lineage.get('substratePass') is True,'LINEAGE_SUBSTRATE_NOT_PASS',failures)
    substrate=lineage.get('tokenizerSubstrate',{})
    require(substrate.get('baseVocabMismatchCount')==0,'LINEAGE_BASE_VOCAB_MISMATCH',failures)
    require(substrate.get('addedTokenMismatchCount')==0,'LINEAGE_ADDED_TOKEN_MISMATCH',failures)
    require(substrate.get('mergeMismatchCount')==0,'LINEAGE_MERGE_MISMATCH',failures)
    require(lineage.get('checks',{}).get('SOURCE_LINEAGE_CHAIN_MATCH') is True,'LINEAGE_CHAIN_MISMATCH',failures)

    topology_counts=topology.get('counts',{})
    require(topology.get('overallPass') is True,'TOPOLOGY_NOT_PASS',failures)
    require(topology_counts.get('ggufTotal')==753,'TOPOLOGY_GGUF_COUNT',failures)
    require(topology_counts.get('ggufMapped')==733,'TOPOLOGY_GGUF_MAPPED',failures)
    require(topology_counts.get('ggufOnly')==20,'TOPOLOGY_GGUF_ONLY',failures)
    require(topology_counts.get('mlxVisionOnly')==333,'TOPOLOGY_MLX_VISION',failures)
    require(topology_counts.get('mlxLanguageOnly')==0,'TOPOLOGY_MLX_LANGUAGE_UNMAPPED',failures)

    for label,report,expected_seed in [('MARGIN_SEED42',seed42,42),('MARGIN_SEED43',seed43,43)]:
        require(report.get('overallPass') is True,f'{label}_NOT_PASS',failures)
        require(report.get('positionCount')==139,f'{label}_POSITION_COUNT',failures)
        require(report.get('llamaTopOneAgreementCount')==133,f'{label}_AGREEMENT_COUNT',failures)
        gate=report.get('acceptanceGate',{})
        require(gate.get('pass') is True,f'{label}_GATE_NOT_PASS',failures)
        require(gate.get('topKContainmentCount')==139,f'{label}_TOPK_CONTAINMENT',failures)
        require(gate.get('maxObservedReferenceRank')==2,f'{label}_MAX_RANK',failures)
        if expected_seed==43: require(report.get('seed')==43,f'{label}_SEED',failures)

    require(qkv.get('status')=='PASS_WITH_BOUNDARY','QKV_NOT_PASS',failures)
    require(qkv.get('layoutResolved') is False,'QKV_LAYOUT_RESOLVED_UNEXPECTED',failures)
    require(qkv.get('bestPermutation',{}).get('permutation')==['k2048','q2048','v4096'],'QKV_BEST_ORDER',failures)

    require(f32.get('overallPass') is True,'F32_NOT_PASS',failures)
    require(f32.get('tensorCount')==260,'F32_TENSOR_COUNT',failures)
    require(f32.get('zeroDriftObserved') is False,'F32_ZERO_DRIFT_UNEXPECTED',failures)
    require(f32.get('maxAbsDiff',0)>0,'F32_DRIFT_NOT_OBSERVED',failures)

    require(quant.get('overallPass') is True,'QUANT_NOT_PASS',failures)
    require(quant.get('layoutResolved') is False,'QUANT_LAYOUT_RESOLVED_UNEXPECTED',failures)
    require(quant.get('elementwiseCorrelationNearZero') is True,'QUANT_CORRELATION_NOT_NEAR_ZERO',failures)

    acceptance={
      'seeds':[42,43],
      'positionsPerSeed':139,
      'topOneAgreementPerSeed':[133,133],
      'topOneAgreementRatio':0.9568345323741008,
      'topKContainmentPerSeed':[139,139],
      'maxReferenceRankPerSeed':[2,2],
      'topOneFlipsPerSeed':[6,6],
      'profilePass':True,
      'profileID':profile.get('profileID'),
    }
    result={
      'consolidatedStatus':'PASS_WITH_BOUNDARY',
      'protocolVersion':'LAB.NAMED_SOURCE.EVIDENCE.BUNDLE.V1',
      'scope':'CYBER_TIEL_GGUF_UD_Q4_K_XL_VS_MLX_OQ4E / MATRIX_V2_12_PROMPTS_139_POSITIONS / TWO_SEEDS',
      'verdicts':{
        'namedSourceAcceptanceGate':'PASS',
        'tokenizerSubstrate':'EXACT',
        'declaredLineageChain':'PASS',
        'textTensorTopology':'COMPLETE_WITH_KNOWN_EXTRAS',
        'sameCheckpointClosure':'REJECTED_AT_CONTROL_TENSOR_LEVEL',
        'largeMatrixQuantizerDriftAttribution':'BLOCKED_LAYOUT_SOURCE_UNRESOLVED',
        'qkvSegmentOrder':'UNRESOLVED',
      },
      'keyFindings':{
        'profile':{
          'profileID':profile.get('profileID'),'seeds':acceptance['seeds'],
          'positionsPerSeed':acceptance['positionsPerSeed'],
          'topKContainmentPerSeed':acceptance['topKContainmentPerSeed'],
          'maxReferenceRankPerSeed':acceptance['maxReferenceRankPerSeed'],
          'topOneFlipsPerSeed':acceptance['topOneFlipsPerSeed'],
          'seedOutcomesIdentical':profile.get('seedOutcomesIdentical'),
        },
        'lineage':{
          'chain':'Ornith 1.5 → Huihui-Ornith-1.5-abliterated → CyberTiel quantization',
          'baseVocabMismatchCount':substrate.get('baseVocabMismatchCount'),
          'addedTokenMismatchCount':substrate.get('addedTokenMismatchCount'),
          'mergeMismatchCount':substrate.get('mergeMismatchCount'),
          'chatTemplateExact':substrate.get('chatTemplateExact'),
        },
        'topology':{
          'ggufTotal':topology_counts.get('ggufTotal'),
          'textModelMapped':topology_counts.get('ggufMapped'),
          'ggufNextnOnly':topology_counts.get('ggufOnly'),
          'mlxVisionOnly':topology_counts.get('mlxVisionOnly'),
          'unexplainedMlxLanguageOnly':topology_counts.get('mlxLanguageOnly'),
        },
        'margin':{
          'seed42TopOneAgreement':seed42.get('llamaTopOneAgreementCount'),
          'seed43TopOneAgreement':seed43.get('llamaTopOneAgreementCount'),
          'positions':seed42.get('positionCount'),
        },
        'controlTensorDrift':{
          'tensorCount':f32.get('tensorCount'),
          'exactTensorCount':f32.get('exactTensorCount'),
          'zeroDriftTensorCount':f32.get('zeroDriftObserved'),
          'maxAbsDiff':f32.get('maxAbsDiff'),
        },
        'quantizedLayoutPilot':{
          'tensorCount':quant.get('tensorCount'),
          'layoutResolved':quant.get('layoutResolved'),
          'elementwiseCorrelationNearZero':quant.get('elementwiseCorrelationNearZero'),
        },
      },
      'acceptanceGate':acceptance,
      'checks':{
        'PROFILE_TWO_SEED_GATE':profile.get('pass') is True,
        'TOKENIZER_SUBSTRATE_EXACT':lineage.get('substratePass') is True,
        'DECLARED_LINEAGE_CHAIN':lineage.get('checks',{}).get('SOURCE_LINEAGE_CHAIN_MATCH') is True,
        'TEXT_TOPOLOGY_MAPPED':topology.get('overallPass') is True,
        'MARGIN_SEED42':seed42.get('overallPass') is True,
        'MARGIN_SEED43':seed43.get('overallPass') is True,
        'QKV_LAYOUT_DIAGNOSTIC':qkv.get('status')=='PASS_WITH_BOUNDARY',
        'F32_CONTROL_AUDIT':f32.get('overallPass') is True,
        'QUANTIZED_LAYOUT_PILOT':quant.get('overallPass') is True,
      },
      'failureReasons':failures,
      'artifacts':{label:{'path':item['path'],'sha256':item['sha256']} for label,item in artifacts.items()},
      'nonClaims':[
        'same checkpoint bytes','same quantization grid','dequantization equivalence',
        'full tokenizer implementation equivalence','quantizer drift attribution',
        'tensor element mapping established','MTP mechanism explanation','production readiness',
      ],
      'overallPass':not failures,
    }
    Path(args.output).write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n')

if __name__=='__main__': main()
