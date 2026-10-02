# SimiGo-Lab Next Session Entry

登记时间：2026-10-02
状态：`G3_MAINLINE_CLOSED / T1_PINNED / AWAITING_FRESH_SESSION_EXECUTION`

本文件是新会话的快速入口，不替代 `docs/RESEARCH_STATE.md` 的权威状态。

## Recovery order

1. 检查 Git 状态与最近提交，不从旧会话记忆恢复。
2. 读 `docs/AGENT_CONTEXT.md` 的 source-of-truth、recovery、boundary规则。
3. 读 `docs/RESEARCH_STATE.md`；最新结论优先看文件尾部 2026-09-29 sections。
4. 读 `docs/00-governance/SIMIGO_LAB_OVERSIZED_RESEARCH_BOUNDARY_FREEZE_20260929.md`。
5. 读 Phase A 审计：
   - `docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_PHASE_A_BOUNDARY_AUDIT_20260929.md`
6. 读 Phase A external review：
   - `docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_PHASE_A_EXTERNAL_REVIEW_20260930.md`
7. 读 registered Phase B opening：
   - `docs/00-governance/SIMIGO_LAB_PALACE1_MINIMAL_DURABLE_UNIT_DRAFT_20260930.md`
8. 读 Phase B draft review：
   - `docs/00-governance/SIMIGO_LAB_PALACE1_PHASE_B_DRAFT_EXTERNAL_REVIEW_20260930.md`
9. 读 Phase B opening registration：
   - `docs/00-governance/SIMIGO_LAB_PALACE1_PHASE_B_OPENING_REGISTRATION_20260930.md`
10. 读 Phase B audit：
   - `docs/00-governance/SIMIGO_LAB_PALACE1_MINIMAL_DURABLE_UNIT_AUDIT_20260930.md`
11. 读 Phase B audit review：
   - `docs/00-governance/SIMIGO_LAB_PALACE1_PHASE_B_AUDIT_EXTERNAL_REVIEW_20260930.md`
12. 读 Phase B audit registration：
   - `docs/00-governance/SIMIGO_LAB_PALACE1_PHASE_B_AUDIT_REGISTRATION_20260930.md`
13. 读 Phase C opening draft（含对 09-28 BACKEND-1 opening 的对照审阅）：
   - `docs/00-governance/SIMIGO_LAB_BACKEND1_PHASE_C_OPENING_DRAFT_20260930.md`
14. 读 Phase C opening draft review：
   - `docs/00-governance/SIMIGO_LAB_BACKEND1_PHASE_C_OPENING_DRAFT_EXTERNAL_REVIEW_20260930.md`
15. 读 Phase C opening registration：
   - `docs/00-governance/SIMIGO_LAB_BACKEND1_PHASE_C_OPENING_REGISTRATION_20260930.md`
16. 读 Phase C seam audit：
   - `docs/00-governance/SIMIGO_LAB_BACKEND1_PHASE_C_SEAM_AUDIT_20260930.md`
17. 读 Phase C seam audit review：
   - `docs/00-governance/SIMIGO_LAB_BACKEND1_PHASE_C_SEAM_AUDIT_EXTERNAL_REVIEW_20260930.md`
18. 如需原始 opening，再读：
   - `docs/00-governance/SIMIGO18_PALACE1_EXECUTION_STATE_STORAGE_RESEARCH_OPENING_20260928.md`
   - `docs/00-governance/SIMIGO18_BACKEND1_LLAMA_RESEARCH_OPENING_20260928.md`
19. 读 BACKEND-1 adapter engineering opening draft：
   - `docs/00-governance/SIMIGO_LAB_BACKEND1_ADAPTER_ENGINEERING_OPENING_DRAFT_20260930.md`
20. 读其 external review：
   - `docs/00-governance/SIMIGO_LAB_BACKEND1_ADAPTER_ENGINEERING_OPENING_EXTERNAL_REVIEW_20260930.md`
21. 读其 registration：
   - `docs/00-governance/SIMIGO_LAB_BACKEND1_ADAPTER_ENGINEERING_OPENING_REGISTRATION_20260930.md`
22. 读 Engineering Round 1 audit：
   - `docs/00-governance/SIMIGO_LAB_BACKEND1_ADAPTER_ENGINEERING_AUDIT_20260930.md`
23. 读其 external review：
   - `docs/00-governance/SIMIGO_LAB_BACKEND1_ADAPTER_ENGINEERING_EXTERNAL_REVIEW_20260930.md`
24. 读 Seam Stability opening draft：
   - `docs/00-governance/SIMIGO_LAB_SEAM_STABILITY_OPENING_DRAFT_20260930.md`
25. 读其 external review：
   - `docs/00-governance/SIMIGO_LAB_SEAM_STABILITY_OPENING_DRAFT_EXTERNAL_REVIEW_20260930.md`
26. 读 Seam Stability audit：
   - `docs/00-governance/SIMIGO_LAB_SEAM_STABILITY_AUDIT_20260930.md`
27. 读其 external review：
   - `docs/00-governance/SIMIGO_LAB_SEAM_STABILITY_AUDIT_EXTERNAL_REVIEW_20260930.md`
28. 读 Architecture Contract opening draft：
   - `docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_ARCHITECTURE_CONTRACT_OPENING_DRAFT_20260930.md`
29. 读其 external review：
   - `docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_ARCHITECTURE_CONTRACT_OPENING_DRAFT_EXTERNAL_REVIEW_20260930.md`
30. 读其 registration：
   - `docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_ARCHITECTURE_CONTRACT_OPENING_REGISTRATION_20260930.md`
31. 读 Contract v1.0 synthesis draft：
   - `docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_ARCHITECTURE_CONTRACT_V1_DRAFT_20260930.md`
32. 读其 external review：
   - `docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_ARCHITECTURE_CONTRACT_V1_EXTERNAL_REVIEW_20260930.md`
33. 读 Contract v1.0-amended（七操作 lifecycle，freeze candidate）：
   - `docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_CONTRACT_V1_AMENDED_20261002.md`
34. 读当前活跃 gate draft（participant proposal，未注册）：
   - `docs/00-governance/SIMIGO_LAB_PALACE1_LIFECYCLE_STORAGE_OPENING_DRAFT_20261002.md`
35. 读其 external review（PASS / ACTIVATION_REQUIRED）：
   - `docs/00-governance/SIMIGO_LAB_PALACE1_LIFECYCLE_STORAGE_OPENING_DRAFT_EXTERNAL_REVIEW_20261002.md`
36. 读 registration 工件（REGISTERED / ACTIVATED）：
   - `docs/00-governance/SIMIGO_LAB_PALACE1_LIFECYCLE_STORAGE_OPENING_REGISTRATION_20261002.md`
37. 读 Gate① 设计草案（仅设计，无执行授权）：
   - `docs/00-governance/SIMIGO_LAB_PALACE1_GATE1_CREATE_IDENTITY_RESERVATION_DESIGN_20261002.md`
38. 读 Gate① 冻结审查登记（PASS — DESIGN FROZEN / EXECUTION NOT AUTHORIZED，含 R-1/R-2/R-3 判读覆盖）：
   - `docs/00-governance/SIMIGO_LAB_PALACE1_GATE1_DESIGN_FREEZE_REVIEW_20261002.md`
39. 读方向变更登记（LIFECYCLE STORAGE PARKED / RIW ENTRY OPEN）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_REAL_INFORMATION_WORKFLOW_DIRECTION_REGISTRATION_20261002.md`
   - ⚠️ 该登记 RIW 入口已被 V2 取代（工件保留作方向演化记录）
40. 读 V2 方向登记（现行有效）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_DIRECTION_REGISTRATION_20261002.md`
41. 读 G0 审计协议草案（仅审计设计，无执行授权）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G0_MEMORY_BACKEND_AUDIT_PROTOCOL_20261002.md`
   - ✅ 已冻结获批（FROZEN / APPROVED，执行授权生效：MemPalace → Mem0 → Graphiti 逐系统中间观察）
42. 读 G0 中间观察 ① — MemPalace（静态源码级）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G0_MEMPALACE_OBSERVATION_20261002.md`
43. 读 G0 中间观察 ② — MemPalace 运行时实测（RQ-1/RQ-3/RQ-7 已答）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G0_MEMPALACE_RUNTIME_OBSERVATION_20261002.md`
   - ✅ MemPalace Observation Set FROZEN（human 2026-10-02；RQ-PALACE-01/02/03 登记为 G0 输出问题）
44. 读 G0 中间观察 ③ — Mem0（静态源码级）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G0_MEM0_OBSERVATION_20261002.md`
45. 读 G0 中间观察 ④ — Graphiti（静态源码级，H-G0-01 判定性样本）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G0_GRAPHITI_OBSERVATION_20261002.md`
46. 读 G0 结论门工件（AUDIT_RESULT 九节+决策输入）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G0_MEMORY_BACKEND_AUDIT_RESULT_20261002.md`
   - ✅ human 三项裁定：G0 CLOSED / Substrate W / G1 UNLOCKED
47. 读 G1 Real Corpus 设计草案（仅设计，无执行授权）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_REAL_CORPUS_DESIGN_DRAFT_20261002.md`
   - ✅ 冻结审查 PASS（执行授权仅限 Corpus-1 选族只读侦察）
48. 读 Corpus-1 选族清单（侦察完成，待 human 确认）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_CORPUS1_SELECTION_20261002.md`
   - ✅ human 裁定：CORPUS-1 = APPROVED（A+D 执行；B1 暂缓 Corpus-1B；「溯源」= 实际观察任务不预定义 Provenance）
49. 读 G1 初始可发现性实验记录（substrate-agnostic 基线 + 三查询）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_CORPUS1_INITIAL_DISCOVERABILITY_20261002.md`
   - 基线证据：`docs/02-evidence/palace-v2-g1-corpus1/baseline-inventory.json`
   - ✅ human 放行主探针（why-continue 原样记录 = H-G1-02 材料；发现不命名 lineage/relation/provenance）
50. 读 G1 主探针记录（内容级事实 + 工作过程轨迹 + H 判定材料）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_MAIN_PROBE_20261002.md`
   - ✅ human 结果门裁定：主探针 PASS；C-1/2/3/5 OBSERVED、C-4 PARTIAL；H-G1-01 SUPPORTED—exploratory；H-G1-02 UNVERIFIED+state-dependency-signal；下一实验 = OQ-B
51. 读 G1 结果门裁定登记（含 H 边界 + 强表述 + 四类证据）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_RESULT_GATE_20261002.md`
52. 读 OQ-B 漂移观察设计草案（仅设计，无执行授权）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_OQB_DRIFT_DESIGN_DRAFT_20261002.md`
   - ✅ 冻结审查 PASS / EXECUTION AUTHORIZED（OB-3 保持观察性质不预判；核心 = OB-4 世界变化后的继续性）
53. 读 OQ-B 结果记录（OB-1..4 + 表示噪声发现）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_OQB_RESULT_20261002.md`
   - ✅ human 验收：OQ-B PASS/CLOSED；OB-4 = HIGH-VALUE EVIDENCE（「工作记录与世界当前状态在最小漂移场景中出现独立性」登记）；RQ-OQB-1 ACCEPT
54. 读 RQ-OQB-1 复测结果（Excel 原生编辑 = 1 cell 变化，噪声为 openpyxl 特有）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_RQOQB1_NATIVE_EXCEL_RESULT_20261002.md`
55. 读 E6 设计草案（FROZEN / EXECUTION AUTHORIZED）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_E6_INFORMATION_VALIDITY_DESIGN_DRAFT_20261002.md`
56. 读 E6 结果记录（V-1..V-5 + 金质性 V-5 案例）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_E6_RESULT_20261002.md`
   - ✅ human 验收：E6 PASS/CLOSED（V-1..V-5 全 PASS）；V-5 提升登记（案例一记录-现实可区分性 bounded evidence + 案例二粒度效应）
57. 读 G1 收束/G2 入口登记：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_CLOSED_G2_ENTRY_20261002.md`
   - ✅ human 确认：G2 设计草案起草批准（四要点：RQ 低于抽象层 / P3=探针非答案 / 过程完整记录 / 禁止架构化升级）
58. 读 G2 设计草案（仅设计，无执行授权）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G2_CROSS_DOCUMENT_WORK_DESIGN_DRAFT_20261002.md`
   - ✅ 冻结审查 PASS / EXECUTION AUTHORIZED（口径包含=判定规则不升级；来源标注=记录要求非 Provenance Schema）
59. 读 G2 执行记录（T-1/T-2/T-3 + OB-A..D）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G2_EXECUTION_20261002.md`
   - 证据：`docs/02-evidence/palace-v2-g2-corpus1/t1-mapping-results.json`
   - ✅ human 结果门裁定：G2 PASS/CLOSED（T-1/T-2/T-3 全 PASS；OB-A..D 全 SUPPORTED）；H-G1-02 升格 SUPPORTED (strong exploratory)；ES 必要性 UNPROVEN 不变；G3 UNLOCKED
60. 读 G2 结果门裁定登记（含 G3 第一问与观察四类）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G2_RESULT_GATE_20261002.md`
   - ✅ human 裁定：G2 结果门通过（H-G1-02 升 SUPPORTED strong exploratory）；RQ-OQB-1 ACCEPT→已执行答案在档；G1 收束不扩 Corpus
61. 读 G3 设计草案（仅设计，无执行授权）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G3_DURABLE_INFORMATION_DESIGN_DRAFT_20261002.md`
   - ✅ 冻结审查 PASS / EXECUTION AUTHORIZED（三类计数口径；B 原样性执行期纪律；OB-R3/R4 重点）
62. 读 G3 结果记录（R-1..R-5 + 重做量对照 + 五项恢复矩阵）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G3_RESULT_20261002.md`
   - ✅ human 结果门裁定：G3 PASS/CLOSED；H-G1-02 升格 SUPPORTED—strong exploratory（冻结措辞在案）；ES 必要性 UNPROVEN；V1 PARKED/G2 不复测/E6·OQ-B 暂不扩展；下一入口 = RQ-G3-1/RQ-G3-2
63. 读 G3 结果门裁定登记（含冻结措辞/证据链收束/三候选形态/负知识）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G3_RESULT_GATE_20261002.md`
   - ✅ human 方向裁定：RQ-G3-1 优先（排除项可能更快触及 PALACE 核心）；最小路径与观察点 ①..⑤ 冻结概念
64. 读 RQ-G3-1 设计草案（仅设计，无执行授权）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_RQG3_1_NEGATIVE_KNOWLEDGE_DESIGN_DRAFT_20261002.md`
   - ✅ 冻结审查 PASS / EXECUTION AUTHORIZED（条件 A 不可见 E-X 历史记录；E-X4 只记观察；④ 三结果均可）
65. 读 RQ-G3-1 结果记录（①..⑤ + E-X1 排除冲突 + 0308 孪生版发现）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_RQG3_1_RESULT_20261002.md`
   - ✅ human 结果门裁定：RQ-G3-1 PASS/CLOSED；E-X1「相邻主题」排除撤销→历史记录；经济运行族纳入候选语料；0308 纳入扩展样本（新增验证样本/后发现版本标记）；经济工作进展维持排除；RQ-G3-2 UNLOCKED（双轴焦点）
66. 读 RQ-G3-1 结果门裁定登记（E-X1 拆分重裁 + 只存结论的危险 + H 更新）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_RQG3_1_RESULT_GATE_20261002.md`
   - ✅ human 方向确认：边界问题已比最初清楚（PALACE=信息空间/世界中「有什么·曾发现·曾如何判断」；SimiGo=「我正在做什么·走到哪里·为什么下一步这样走」）；G3 实证 L0 ≠ L0+工作状态记录且未证后者必须由 SimiGo 提供——边界干净
   - ✅ 下一步方向 = Boundary Study（核心问 = 同一信息世界两工作者为何不能互相恢复工作状态；四情况矩阵 + ES 候选边界六问；终态公式 = PALACE 负责「世界」/ SimiGo 负责「人在世界中的持续行动」）
67. 读 Boundary Study 方向登记：
   - `docs/00-governance/SIMIGO_LAB_PALACE_SIMIGO_BOUNDARY_STUDY_DIRECTION_20261002.md`
   - ✅ human 确认：RQ-G3-2 设计起草（双轴；不比格式优劣；测可恢复·可质询·可修正；两故障锚点；不预设原样为最终答案）
68. 读 RQ-G3-2 设计草案（仅设计，无执行授权）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_RQG3_2_RECORD_SPECTRUM_DESIGN_DRAFT_20261002.md`
   - ✅ 冻结审查 PASS / EXECUTION AUTHORIZED（四档真隔离；非压缩率实验；不倾向 Tier-4；γ 最值得关注）
69. 读 RQ-G3-2 结果记录（四问矩阵 + 双轴分离实证 + crown findings）：
   - `docs/00-governance/SIMIGO_LAB_PALACE_V2_RQG3_2_RESULT_20261002.md`
   - ✅ human 主线收束裁定：四问矩阵 PASS/CLOSED（continue ≠ audit/review 两维度）；CF-①② 双 HIGH VALUE/ACCEPTED；G3 = CLOSED（五项工作恢复要素登记非 Schema）；RQ-G3-3 转向；PALACE-SimiGo Boundary Study ENTRY OPEN
70. 读 G3 收束与 Boundary Study 入口登记：
    - `docs/00-governance/SIMIGO_LAB_PALACE_V2_G3_CLOSED_BOUNDARY_STUDY_ENTRY_20261002.md`
71. 读 Boundary Study 设计草案（仅设计，无执行授权）：
    - `docs/00-governance/SIMIGO_LAB_PALACE_SIMIGO_BOUNDARY_STUDY_DESIGN_DRAFT_20261002.md`
72. 读 Boundary Study 设计冻结审查登记（三项审查全 PASS；同日 §12 修订）：
    - `docs/00-governance/SIMIGO_LAB_PALACE_SIMIGO_BOUNDARY_STUDY_DESIGN_FREEZE_REVIEW_20261002.md`
    - ✅ human 冻结指令：DESIGN FROZEN / EXECUTION NOT STARTED / 首实验授权 = 仅最小 A→B 接续实验（四 case 全量待首实验结果门）；B 行为六类 + Boundary Evidence Table + 闭合原则链冻结；新增禁令（数据库/PALACE Schema/大文件归属/多子库/PALACE API/RAG 化/修改 SimiGo ES）
73. 读 Boundary Study 设计修订登记（ES 语义精化，同日第二次修订；三项审查重跑 PASS×3）：
    - `docs/00-governance/SIMIGO_LAB_PALACE_SIMIGO_BOUNDARY_STUDY_DESIGN_REVISION_EXEC_SEMANTICS_20261002.md`
    - ✅ human 概念精化：ES = 具有执行语义的信息（PALACE 信息空间中的特殊信息类，非对立面）；精确问 = 哪些信息仅可描述、哪些必须保持 ES 语义才能继续执行；首实验探针修订 = 完整保存 → 恢复 → 逐项语义存活观察（Evidence Table v2 取代 v1）；判别力门 = 任务须自然产生 ⑥⑦⑧ 类事件；设计草案 §13 = operative 读法
74. 读设计草案 §14（判据精化 + 设计封笔）与 STEP 0 提名呈现：
    - ✅ S1 可解释/S2 可继续两层（Alive = S2 ✓）；Replay Cost R0–R4 记录现象（正式定义延后）；Continuation ≠ Re-solving 最强 guard（首实质动作 = 停止点下一合法操作）；反裁剪纪律（不为实验成功设计 PALACE 擅长保存的结构）；设计封笔（再改须新 human 方向）
    - ✅ STEP 0 提名 = X1（0307/0308 孪生差异整理）/ X2（S8 缺口闭合）/ Y（RQ-G2-1 验证执行），六项检查全过，推荐 X1；待 human 钉定任务 X + 确认 A/B 承担方式
75. 读 EXP1-X1 实验记录与 A 半程结果：
    - `boundary-study/exp1-x1/RECORD.md`（STEP 0 钉定逐字 + A 停止点逐字 + 停止点形态偏离登记）
    - `boundary-study/exp1-x1/00-MANIFEST.md`（信息空间钉定 + SHA256 + 组成裁定）
    - `boundary-study/exp1-x1/information-space/a-deposits/`（A 沉淀 7 件，主产出 = 版本差异报告.md）
    - `boundary-study/exp1-x1/truth/`（封存：A 任务指令逐字 + 动作日志；Evidence Table 完成前不用于判读）
    - ✅ human 钉定 = X1 / A 独立新会话（任务指令零框架）/ B 独立新会话由 Agent 扮演（仅收接续语 + 信息空间）；授权 commit e66e723 先于 A 工作；A 约 17 分钟自然完成（前沿 = 遗留事项 1–3 非中途差异条目——偏离已登记，检验仍良定义）；**待 human 裁定 B 放行**
76. 读 EXP1-X1 B 半程结果与 Boundary Evidence Table v2：
    - `boundary-study/exp1-x1/RESULTS.md`（结果门材料）
    - `boundary-study/exp1-x1/RECORD.md` §4–§5（B 放行裁定逐字 + B 运行事实）
    - `boundary-study/exp1-x1/observation/b-action-chain.txt`（B 完整动作链，仪器先于 spawn 提交）
    - `boundary-study/exp1-x1/b-workspace/`（B 产出：核查与续作报告.md 等 12 件）
    - ✅ human 双裁定 = 停止点形态 ACCEPT + B RELEASED（输入 = 仅续接语 + 信息空间）；B 通读空间后「先复核存款载荷再做新核查」→ 抓到存款提取折叠缺陷 + 「须回引 0307」错误判断 → 0308 自洽核查 28 项 → 遗留清单 3→12 条；判定 = 验证式重做→真续作（混合形态）；表七行归属 + F-1..F-6 发现（F-2 信任不随保存传递 / F-4 显式待办 = 最强存活形态 / F-5 最小条件候选 (c) 可信性保证不在信息本身——本实验信息可闭合，ES 候选化条件指向候选 Y）；**待 human 结果门判读**

## Current snapshot

```text
branch = codex/execution-state-research-20260929
route = EXECUTION-STATE-CENTRIC
runtime line = SEALED / BOUNDED CONSOLIDATION
architecture contract = PHASE A REVIEW PASS / REGISTERED
BACKEND-1 = ENGINEERING ROUND1 COMPLETE / PASS / REGISTERED / CLOSED
SEAM-STABILITY = AUDIT PASS / REGISTERED / CLOSED
ARCH-CONTRACT = OPENING REGISTERED / SYNTHESIS COMPLETE / V1 REGISTERED / UPSTREAM REFERENCE
Contract v1.0-amended = FREEZE CANDIDATE / AWAITING FINAL FREEZE DECLARATION（human）
oversized = FROZEN / ARCHITECTURE VALIDATION PAYLOAD
PALACE = V2 G2 PASS/CLOSED（T-1/T-2/T-3 全 PASS；OB-A..D 全 SUPPORTED）→ G3 Durable Information UNLOCKED / DESIGN ENTRY：第一问（human 原语）= 「如果今天把当前工作停止，明天重新打开，我究竟需要什么，才能真正从这里继续，而不是重新做一遍？」观察四类 = 已发现/已判断/已排除/下一步为什么；现实成本 = 只剩原始文件则须重做 T-1/T-2；H-G1-01 SUPPORTED—strengthened / H-G1-02 SUPPORTED (strong exploratory)；ES 必要性 UNPROVEN 不变；G3 不重新定义 Execution State——PALACE 与 SimiGo 边界让工程逼出；SimiGo = PARKED 不变（上下游待 G3 工程事实）
next mode = REPLICATION_AUDIT_PHASE1_DAY1_P4_DONE（2026-10-01 下午链：安全事件处置[产品仓 force push 回滚 dc12a0c，研究内容限 Lab 仓]→Empirical Replication Audit Phase-1 签发[R0→P4→P5-1→P5-2-C→P5-4→P7-R2-A，逐步冻结]→R0 自检 ALL CHECKS PASSED→**P4 Replication 执行=机械判读 overall PASS**[判据 792afbc 逐字移植；6 独立进程；R0 runUUID 工件通道；J4 换序 8/8 逐字；隔离 204/2；S₁ 输出与原跑逐字相同=预期对照]——产物+harness 归档 docs/02-evidence/p4-replication-20261001/，结果文档 SIMIGO_LAB_P4_REPLICATION_RESULTS_20261001.md；**当前停：G-LC1+N-1..N-6 全 ACCEPT（G-LC1 附约束=save 是 representation/lifecycle transition 非 semantic closure mutation）→ Contract v1.0-amended 交付（SIMIGO_LAB_EXECUTION_STATE_CONTRACT_V1_AMENDED_20261002.md：lifecycle 扩七操作[create 补入/save 第七操作附约束/restore fail-closed/eviction 归 release 族]/N-1 INV-XB 内联/N-2 映射义务/N-5 方向性声明/N-6 版本钉定电池/N-4 附录 A·B 两份正式 Representation Declaration[R_llama/R_MLX 含 invariant→rule 映射]）→ 纯文本一致性复核 PASS（七项，含 save 约束 vs ES-D1 formation 边界相容[formation=同一 closure 转入 durable representation 非变异]）→ **FINAL FREEZE DECLARATION 归 human ⇒ SimiGo v2.0 Contract / Public Architecture Freeze**）**
```

2026-09-29 route redefinition:

- Runtime correctness evidence is no longer a main expansion line.
- Oversized independent research is frozen and retained only as validation payload.
- PALACE-1 and BACKEND-1 are no longer treated as two immediately parallel implementation tracks.
- A new Execution State Architecture Contract synthesis gate comes first.
- The next audit must classify current runtime state touches as Durable Semantic State (D),
  Runtime Binding (R), Physical Representation (P), Observability/History (O), or
  Transient/Reconstructable (T).
- Storage technology selection and Llama adapter implementation remain unauthorized.

2026-09-29 Phase A result:

- Audit completed for the current Lab runtime code only; no storage was selected.
- The inferred minimal D closure is the semantic `ExecutionStateHandle` aggregate:
  id, lineage, position, continuation, lifecycle.
- `RepresentationRef`, bindings, lifecycle history, artifact sidecars, pool stats,
  and physical-use state are not part of the minimal D closure.
- Durable Execution State and durable representation reattachment must remain
  separate boundary decisions.
- Targeted contract/pool/store/materialization/atomicity tests passed 45/45.

2026-09-30 external review:

- Verdict: `PASS / REGISTRATION_REQUIRED`.
- Review is not repository registration.
- Phase B remains closed until explicit human/repository registration.
- Six non-blocking conditions are registered for Phase B:
  durable identity allocation, continuation-vs-transcript equivalence,
  representation content claim, separate binding persistence boundary,
  crash-consistency semantics, and the discarded-binding gap.

2026-09-30 Phase B draft:

- A PALACE-1 minimal durable unit opening draft is now available.
- It is a participant proposal only.
- Phase B remains closed until the Phase A review decision is explicitly
  registered.

2026-09-30 Phase B draft review:

- Verdict: `PASS / ACTIVATION_REQUIRED`.
- The draft now includes interrupted fork / continue / restore recovery windows.
- Review is not activation; Phase B remains closed.
- One explicit human registration can approve both the Phase A PASS and the
  reviewed Phase B opening.

2026-09-30 explicit registration:

- Human instruction: `登记两项 PASS，并激活 Phase B opening。`
- Phase A review PASS is registered.
- Phase B draft review PASS is registered.
- The reviewed Phase B draft is activated as the PALACE-1 opening.
- Phase B is now open only for code-level architecture audit.

2026-09-30 Phase B audit:

- Audited clean HEAD `db188ac`; unrelated dirty Swift files in the main worktree
  were not mixed into evidence.
- Named the contract-level minimal durable unit `Execution Semantic Snapshot`.
- A recoverable set is the closure of snapshots plus required lineage tombstones.
- `continuation.nextInput` remains D in the current Lab contract.
- RepresentationRef and binding relations remain separate from minimum D.
- Full lifecycle records, pool stats, and in-flight work are not minimum D.
- Targeted clean-HEAD tests passed 57/57.

2026-09-30 Phase B audit review:

- Verdict: `PASS / REGISTRATION_REQUIRED`.
- Review is not repository registration.
- Phase C / BACKEND-1 remain gated until the Phase B boundary is registered.
- Six mandatory conditions carry forward: lineage tombstone closure,
  transcript equivalence proof, representation content claim, separately typed
  binding relation, crash-window classification, and concurrency/identity gaps.

2026-09-30 Phase B audit registration:

- Human instruction: `登记 Phase B audit PASS。`
- Registration artifact:
  `docs/00-governance/SIMIGO_LAB_PALACE1_PHASE_B_AUDIT_REGISTRATION_20260930.md`。
- Phase B boundary audit `PASS` is registered; minimal durable unit =
  `Execution Semantic Snapshot` is now the registered architecture contract.
- The six mandatory conditions are inherited by every later gate.
- Phase C / BACKEND-1 boundary precondition is SATISFIED; activation still
  requires its own decision point, and the BACKEND-1 opening must be re-reviewed
  against the registered boundary before execution.

2026-09-30 Phase C opening draft + review:

- Human instruction: `开始新研究路线的研究`。
- Participant draft (commit `a5a7177`):
  `docs/00-governance/SIMIGO_LAB_BACKEND1_PHASE_C_OPENING_DRAFT_20260930.md`。
  对照已登记 Phase B boundary 重审了 09-28 BACKEND-1 opening（修正
  RepresentationRef 目标关系与 Q4 前提），产出 re-anchored Phase C opening
  C1–C8（leakage / minimal seam / capability / representation contract /
  sync-async / cancellation-failure-release / default-path 结构性 /
  cross-backend semantic continuity）。
- Draft review verdict: `PASS / ACTIVATION_REQUIRED`。
- Review is not activation; Phase C seam audit remains NOT STARTED.
- Six Phase B conditions + four review strengthening points carry into
  registration; RQ1 cited as prior evidence only, RQ3 stays SEPARATELY SCOPED.
- Current blocker = none on Phase C seam audit.

2026-09-30 explicit Phase C registration:

- Human instruction: `登记 Phase C opening PASS，并激活 Phase C seam audit。`
- Registration artifact:
  `docs/00-governance/SIMIGO_LAB_BACKEND1_PHASE_C_OPENING_REGISTRATION_20260930.md`。
- The re-anchored Phase C opening（C1–C8）is registered.
- Phase C code-level seam audit is now ACTIVE: clean HEAD worktree + targeted
  tests; observed code fact ≠ inferred contract ≠ selected implementation.

2026-09-30 Phase C seam audit + review:

- Audit (commit `58859a9`, clean HEAD `ebe4aec`):
  `docs/00-governance/SIMIGO_LAB_BACKEND1_PHASE_C_SEAM_AUDIT_20260930.md`。
  C1–C8 全部有代码级回答：最小 seam = E1+E3+B1 三契约（已存在并被三异构
  backend 行为验证）；语义层零 MLX 渗漏（唯一渗漏点 PrefixSnapshotStore
  公开 API，G-5/L-1）；sovereignty 结构验证（backend 无语义写路径）；
  10 项 gaps 登记（G-1…G-10）；C8 = 契约支持跨 backend 语义连续（边界内）。
- Evidence: `SimiGoRuntimeContractTests 19/19` + selected
  `SimiGo2ExperimentalTests 42/42` = `61/61 PASS`；summary JSON 在
  `simigo2-experimental/results/backend-conformance/`。
- Audit review verdict: `PASS / REGISTRATION_REQUIRED`。
- Review is not repository registration; four strengthening points carry
  into registration（condition-1 seam 读法 / L-1 处置 / G-1 前置条件 /
  证据卫生）。
- Registered `PASS / REGISTERED` by human-side commit `afdf30f`; Phase C sealed.

2026-09-30 BACKEND-1 adapter engineering opening cycle:

- Opening draft（`2528658`）+ external review（`9ebeaf1`）completed outside
  this session; review verdict `PASS / ACTIVATION_REQUIRED`, Engineering
  NOT AUTHORIZED YET。同日 `1e2749f` 清理 Swift 并发/未用结果告警（纯告警
  修复，非语义变更，不改变审计对象语义）。
- Human instruction directs the explicit registration; registration artifact:
  `docs/00-governance/SIMIGO_LAB_BACKEND1_ADAPTER_ENGINEERING_OPENING_
  REGISTRATION_20260930.md`（本会话执行）。
- Registered validation question: E1+E3+B1 seam 是否足以承载真实 adapter
  engineering，而不把 backend-specific state / representation detail /
  physical lifecycle 重新提升为 Execution Semantic State。
- Registered gate state: Engineering = AUTHORIZED / NOT STARTED; 三分法
  SUFFICIENT / INSUFFICIENT-BUT-LOCAL / CONTRACT-BLOCKED; M-1…M-5 强制检查
  项 + 七条 stop conditions 随登记固化; G-1…G-10 与 Phase B 六条件全部
  inherited / NOT CLOSED。
- Next phase = engineering（A1–A8，先 code-level boundary audit）→ targeted
  evidence → external review → registration。

2026-09-30 Engineering round 1 + second-layer review + external review:

- Engineering 完成（`7f1fa4a` audit / `2cf5adb` impl / `5b47ea8` test）：
  LLAMA backend 定性为 validation payload → reuse+compose 出
  `LLAMAServerExecutionStateAdapter`（E1+E3+真实 transport 组合体，状态全
  R/T/P，commit 前取消门）；T1–T8 14/14，并集 75/75（Phase C 零回归）。
- Engineering 裁决：`SUFFICIENT（有界）`；不自封 gate。
- Human 第二层裁决：认可 SUFFICIENT（有界），A2+A8 同时成立为关键结果；
  B1 不参与 = seam 能力边界原则；固定四审查点；不改 contract、不扩测试面。
- External review verdict: `PASS / REGISTRATION_REQUIRED`；四条 strengthening
  （cancellation containment 术语钉死 / seam 能力边界原则 / stub-live 证据
  分层 / SUFFICIENT 适用域限定）随登记固化。
- Current blocker = explicit human registration。

2026-09-30 Seam stability opening draft + review:

- Human instruction: `从 opening/definition gate 开始`。
- Participant draft（`6d5e08d`）: S1–S6（稳定性四轴 / contract-change 机械
  检查表 / G-gap 风险地图 / second-backend 需求分析（审计级）/ productization
  判据 / standing drift 面）；Stability ≠ immutability 预钉死；verdict
  taxonomy 三分法（STABLE-AS-REGISTERED / STABILITY-CONDITIONAL / UNSTABLE）。
- Draft review verdict: `PASS / ACTIVATION_REQUIRED`；五条 strengthening 随
  登记固化（S4 抽象化 / 轴 d 读法 / S3 非实现队列 / verdict 判据采数前
  固化 / re-run 绑定源码状态）。
- PALACE = SEPARATELY SCOPED 不消费；G-1…G-10 只分类不解决；无实现、无新
  测试、无 contract 变更授权。
- Current blocker = explicit human registration。

2026-09-30 Seam stability audit + review:

- Audit（`33fb410`，source state `b031188`，判据冻结版逐字适用）：
  S1 四轴 SATISFIED（a/b/c 行使层、d 判据层）；S2 = 12 条机械
  contract-change 信号；S3 风险地图 0 × CONTRACT-BLOCKING（1 常备触发
  G-9 + 3 条件触发 G-6/G-7/G-10）；S4 抽象类需求全落点既有 seam；
  S5 六判据只定义；S6 standing 面组装 + re-run 75/75 @ b031188 零漂移。
- 关键新事实：contract target 全部历史 4 commits 均在 2026-09-25，此后
  零变更，横跨全部已登记轮次。
- 裁决：`STABLE-AS-REGISTERED`（有界：≠ immutability / ≠ universal
  portability / ≠ production readiness / ≠ performance）。
- Audit review verdict: `PASS / REGISTRATION_REQUIRED`；四条 strengthening
  （axis-c 观察窗口限定 / 轴 d 再检验为 standing condition / 裁决继承
  Round 1 适用域 / S2 机械检测 standing 最低标准）随登记固化。
- Current blocker = none。

2026-09-30 Architecture Contract opening draft + review:

- Human instruction: 提议 `EXECUTION_STATE_ARCHITECTURE_CONTRACT_OPENING`
  （下一方向 = 把工程事实证明出的语义提升为唯一上游契约；不马上做第二个
  backend、不做 durable store 实现）。
- Participant draft（`0573ec3`）: AC-1 Semantic Core / AC-2 Identity·
  Continuity（same-vs-new State 判据）/ AC-3 Representation Boundary 四态
  结果 / AC-4 Backend Independence 准入标准——route 六问全部收口；合成
  纪律（可追溯 + 冲突即 open point）；契约 v1.0 版本化。
- Draft review verdict: `PASS / ACTIVATION_REQUIRED`；五条 strengthening
  （synthesis ≠ re-litigation / Q5 按 Phase B 先答收口 / AC-2 可机械检验 /
  contract v1.0 成为 drift 参照 / open points 治理）随登记固化。
- Current blocker = explicit human registration。

2026-09-30 Architecture Contract opening registration + synthesis:

- Human instruction: `登记 Architecture Contract opening PASS，并激活
  contract synthesis。` Registration commit `62142ad`（本会话执行）。
- Synthesis（`a1e2e28`）: Contract v1.0 draft 完成——§1 Semantic Core
  分类总表 + 三定律（SC-1 权威/SC-2 snapshot/SC-3 事务窗口，route Q2/Q3
  收口）；§2 Identity·Continuity 法则（SAME/NEW 判据 + IC-1…IC-5 + 判定
  示例，route Q1 收口，用户场景契约化）；§3 Representation Boundary
  （RB-1…RB-8，route Q4/Q5/Q6 收口）；§4 Backend Independence 准入
  BI-1…BI-5；§5 open points ledger OP-1…OP-7（携带不关闭）；§6 drift
  集成（C-13 双向信号）；§7 non-claims。
- 合成纪律遵守：零新增语义、零 open point 静默解决、全部陈述带登记引用。
- Current blocker = none（synthesis 完成）；下一步 = Contract v1.0 的
  external review（second-layer 或 reviewer 角色，由 human 指定）。

2026-09-30 Contract v1.0 external review:

- Human 指令：进入 External Review（暂不做第二层裁决），固定六项审查
  （synthesis fidelity / 五元组法则 / representation sovereignty /
  open-point integrity / bidirectional drift / scope discipline）。
- Review（`a020344`）verdict: `PASS / REGISTRATION_REQUIRED`。六项全 PASS；
  一处表述歧义（「五元组语义保持」≠「值不变」）以 strengthening #1 钉死
  精确读法（identity 锚 = ExecutionID；五字段保持 Runtime 独占、值仅经
  登记生命周期转移演化）；另三条：C-13 程序性检测定位 / BackendMemory
  Observation 行溯源补强 / 升格效果声明。
- Current blocker = explicit human registration。registration 即时生效：
  v1.0 升格为上游语义参照，研究层级切换为 Contract ⇅ 实现侧。

Canonical route document:

`docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_RESEARCH_ROUTE_REDEFINITION_20260929.md`

## Hard boundaries

```text
❌ 不实现 Palace database
❌ 不选定 SQLite / embedded KV / remote service等存储方案
❌ 不直接实现 Llama adapter
❌ 不重启 standalone oversized layer / tensor / loading strategy研究
❌ 不把 oversized scale latency解释为 performance benchmark
❌ 不为 oversized结果给 Execution State增加特殊语义
```

## Next session task

1. 下一会话第一动作：T1 fresh 会话执行（human 已在桌面端
   以 cwd=palace-v0/workspace 开会话并粘贴指令——登记件 §3）
   完成后：定位新 rollout JSONL → 仪器提取 mempalace_* 动作链
   → 七问读数 + 补充位（C-5 感知/C-1 撞上/写回形态/工具用弃）
   → 交付物《数据澄清函》对照 B 的 12 条清单（继承 vs 重发现
   落差）→ palace status 对照基线 9,362（第⑦问）→ 碰撞账本
   更新 → human 判读。纪律：不修 MemPalace；不自研 Schema；
   双向结果皆有效不预判。

继续区分：

```text
observed code fact
≠ inferred storage design
≠ selected implementation
```



### LAB ARCHITECTURE CONTRACT V1 REGISTERED — 2026-09-30

Human/repository registration completed after external review `a020344` with verdict `PASS / REGISTRATION_REQUIRED`.

- Registration artifact:
  `docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_ARCHITECTURE_CONTRACT_V1_REGISTRATION_20260930.md`
- Registered contract artifact:
  `docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_ARCHITECTURE_CONTRACT_V1_DRAFT_20260930.md`
- Five-tuple ambiguity is fixed: Runtime-owned semantic fields evolve only through registered lifecycle transitions; ExecutionID is the identity anchor; representation never directly writes the five fields.
- C-13 is active as procedural gate-check detection; automation remains P-2.
- `BackendMemoryObservation` R classification is recorded as a derivation from passive-observation semantics.
- v1.0 is now the upstream semantic reference. Research hierarchy is `Contract ⇅ code / Runtime / Backend / Persistence`.
- OP-1…OP-7, G-1…G-10, Phase B inherited conditions, M-1…M-5, and Seam Stability S2/S6 remain active; no open point is closed by registration.

Current state:

```text
Contract v1.0 = PASS / REGISTERED
Current blocker = none
Next mode = DRIFT-DETECTION / CONTRACT-GATE-DISCIPLINE
```
77. 读 PALACE 改轨登记与 MemPalace v0 首日观察：
    - `docs/00-governance/SIMIGO_LAB_PALACE_REAL_CARRIER_ROUTE_CHANGE_20261002.md`
    - `docs/00-governance/SIMIGO_LAB_PALACE_REAL_CARRIER_MEMPALACE_V0_INIT_20261002.md`
    - ✅ human 改轨：X1 ACCEPT；Boundary Study 收口（Y = ES Boundary Candidate Probe，REGISTERED/NOT STARTED，四 case 全量不执行）；PALACE = MemPalace 原样跑起来；v0 初始化完成（9,311 drawers：真实语料 54 文件 + EXP1 会话 4 件；palace-v0/ gitignore 隔离）；首日碰撞 C-1..C-5（PDF 全灭/xlsx 压平爆炸/数字检索失真/会话-源文档排序倒挂/wake-up 噪声占据）；0308 在场性裁定 = 排序层失败非缺失层；**待 human 排下一步优先序（a MCP 接入 / b 碰撞处置观察 / c 真实使用 / d Y 探针）**
78. 读 SimiGo MCP 接入记录与首次真实工作实验设计：
    - `docs/00-governance/SIMIGO_LAB_PALACE_MCP_WIRED_FIRST_WORK_DESIGN_20261002.md`
    - `.mcp.json`（项目级，新会话自动加载）
    - ✅ human 优先序 = a→c / b 伴随 / d 冻结 / **a≠修C-5**（wake-up NaN 原样保留）；C-1..C-5 = collision ledger 记录不修；MCP 已接线并端到端验证（44 工具全谱含写回面；search 实调命中）；轨 c 观察七问冻结；**待办 = 第 0 步任务提名 → human 钉定 → fresh 会话真实工作**
79. 读轨 c 修正登记（执行主体 = ZCode；a 收口；提名六准则冻结）：
    - `docs/00-governance/SIMIGO_LAB_PALACE_MCP_WIRED_FIRST_WORK_DESIGN_20261002.md` §5
    - ✅ human 修正 = ZCode 经 MCP 使用 MemPalace（SimiGo 暂在链外）；候选任务六准则冻结（第 6 条最重：不告知「必须使用 PALACE」）；深层观察 = PALACE 会不会被当作「过去工作的可继续空间」；**待办 = human 钉定任务 → fresh 会话执行**
80. 读 PALACE 真实工作实验 T1 执行登记：
    - `docs/00-governance/SIMIGO_LAB_PALACE_REALWORK_T1_REGISTRATION_20261002.md`
    - ✅ human 钉定 = T1 + cwd palace-v0/workspace/ + 指令零泄漏 + 双向有效不预判；palace 基线 9,362 drawers；**待办 = human 桌面端开 fresh 会话（cwd=palace-v0/workspace，approve mempalace server，粘贴登记件 §3 指令）→ 执行后研究侧做动作链提取 + 七问读数 + 交付物审计 + palace 对照**
