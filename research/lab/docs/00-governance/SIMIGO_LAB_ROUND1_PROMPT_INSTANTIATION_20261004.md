# Round 1 Prompt Instantiation

Date: 2026-10-04  
Status: `17 CONDITION PROMPTS INSTANTIATED / RUNTIME AUTHORIZED / OBSERVER NOT AUTHORIZED / STORE NOT AUTHORIZED`

## 1. Scope

This instantiation covers only the seven frozen Round-1 designs, expanded into
17 direct-inline condition arms. The base task, release rules, final-output
shape, model, endpoint, generation settings, and idle-suspend cold-path method
are fixed.

`R-D1` is instantiated as `RD1A-WHOLE-REGISTER` and
`RD1A-STRUCTURED-FACTS`. `R-D1B` is not instantiated.

## 2. Frozen condition arms

RD2-RAW: `5561b61ee3d4d11cd351c53d76da8cc9235c0f17156b2e2aaa529d987e96a91c`
RD2-DECODED-TEXT: `b2797ceae5b3f57be969fb410d3cf0b884effcc5b5888d217882d1c566dacde9`
RD2-SEMANTIC-OBJECT: `ca35e0332889c59101647780fd6bae35d1c59bd43e9e11818d311e1e5643ffbf`
RD5-EXPLANATION-ABSENT: `531a71657557918f7a32b60b3e06a1921f9b5d985967924ae31f9551ca1a1d7d`
RD5-EXPLANATION-PRESENT: `ef4bbc00a7f81d2aab9fd5db1f9a4bb4bc40ce3930264322be0f07f81b258895`
RD1A-WHOLE-REGISTER: `ca35e0332889c59101647780fd6bae35d1c59bd43e9e11818d311e1e5643ffbf`
RD1A-STRUCTURED-FACTS: `d33f0edec594149e21f251f9f58133b102fbea882ab81e34ab106aba70109afa`
RD3-M2-DELETED: `30fea14b936046f28479793417ea320f23c2f5c25bdfe2a0b7f8565c318621a9`
RD4-M1-ALL: `74a317f66aa3e86d017372ea0106861b2a21e61573948e90c769a51241ecb16b`
RD4-M1-GAMMA-ONLY: `531a71657557918f7a32b60b3e06a1921f9b5d985967924ae31f9551ca1a1d7d`
RD4-M1-ABSENT: `da1a6f374bc605d8cb7e37c46446ba898eb55a167ec4a4705a75e936e74ac83d`
RD8-HASH-VALID: `b3ef218555aeee6747f0c642af84714d29bc64c3a74fc03092b5677b7d6cff1c`
RD8-HASH-STALE: `60cf712d3e61332d97366e24c106d8c28cbe0ce7eb6a643a279f908be7163c22`
RD8-HASH-ABSENT: `531a71657557918f7a32b60b3e06a1921f9b5d985967924ae31f9551ca1a1d7d`
RD9-TOOL-PRESENT: `731a97d387ece4b95c6ec111c9ebead7aa463aa9cf5f4ca1183ebdc6bdb57612`
RD9-TOOL-ABSENT: `531a71657557918f7a32b60b3e06a1921f9b5d985967924ae31f9551ca1a1d7d`
RD9-TOOL-SUMMARY: `30a5e95f5147674005c0e0f5f423cd927ab684b5a90c142b4af138c9446f8843`

## 3. Fixed evidence notes

`RD2-RAW` embeds the exact sealed Execution A final-answer bytes, including the
outer JSON string-literal representation.

`RD8-HASH-VALID` embeds the four exact sealed source hashes from Execution A
state. `RD8-HASH-STALE` embeds deterministic different hashes and does not label
them as stale inside the prompt. `RD8-HASH-ABSENT` contains no source hashes.

`RD9-TOOL-PRESENT` embeds the four sealed `read_file` evidence records.
`RD9-TOOL-ABSENT` contains no tool evidence. `RD9-TOOL-SUMMARY` contains only
the four successful-call summaries.

Repeated prompt bytes occur where a control arm is deliberately reused for
another design; each repetition still receives a fresh cold runtime run.

## 4. Authorization boundary

```text
runtime execution       = AUTHORIZED;
raw result capture      = AUTHORIZED;
later adjudication      = AUTHORIZED AFTER RAW CAPTURE;
Observer                 = NOT AUTHORIZED;
InformationCore store    = NOT AUTHORIZED;
schema/API change        = NOT AUTHORIZED;
additional conditions    = NOT AUTHORIZED.
```
