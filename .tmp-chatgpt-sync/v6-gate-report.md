simulator v6 已实现并通过全冻结回归门:commit f1eb28d(引擎+运行产物入档,origin=slamfinger/SimiGo-Lab 已推送)。按你的指示,本轮零 H-P1 采数,结构策略读数仅作门禁自检、禁止判读。

## Regression Gate 结果(exit 0,全 PASS)

**P3-A 冻结复现(逐位)**:
- 主表 8 格全过:hot lru 973.1(696/684)/lfu_aging 544.4(392/380)/V0 547.3(394/382)/belady 475.3(343/331);tree lru 1422.9(1015/1003)/lfu_aging 1085.9(776/764)/V0 1156.4(826/814)/belady 740.4(531/519)
- H 敏感性:H=4 815.2(584)/H=16 547.3(394)全过
- pressure 6 配置全过(hot 1990/1984/1983;tree 1991/1990/1989,三策略同值)
- v4 引擎 ≡ v3 全配置核心字段等价(FAIL x0)

**P3-B 冻结事实**:V0 数字双 workload 全过;V4≡V3 序列逐位 dd=0(hot/tree);hot V2≡V0 dd=0(sat=0 结构产物)

**P3-C 冻结复现**:A≡V4 序列逐位 dd=0(548.7/1133.8);D≡lfu_aging dd=0(544.4/1085.9);C≡诊断(544.4/1084.5);B 采数定格(554.3 399/387;1145.1 818/806,provenance=P3C run 存档+post-802e150 v5 复跑逐位一致)

**H-P1 结构策略门禁自检(6 形态 × 2 workload,全过)**:
- P_S1(−pos)/P_S2(−A_anc)/P_S3(+A_chain)主方向+敏感方向(取反)
- 确定性:同配置重跑 core+seq 逐位一致
- L2 构造审计:信号=窗口计数×静态拓扑纯函数;引擎不预计算 next_use(oracle 不入内存);运行时逐驱逐断言窗口 max step ≤ t,全过
- 一致性下界 dd ≥ |Δrehy|(vs lru 参照行)全过;violations=0

运行产物:runs/HP1_V6_REGRESSION_GATE_PROVENANCE_20260922/v6_gate_stdout.txt

## 门位

v6 Regression Gate PASS → H-P1 Tier-1 采数 UNLOCK(按设计 §3/§4 预注册:L1 事件集=各自 workload 的 lru∪C (node,t) 去重并集;Spearman ρ 双侧;存在性线 |ρ|≥0.1;hot 阴性对照 |ρ|≥0.1 触线停机;L3 主方向 J<J(C) tree Tier-1 + 敏感方向同跑同报)。

一条如实披露:门禁自检跑出了结构策略的 J 读数(如 tree/P_S1=1073.2),但按纪律这些读数禁止判读——正式 L1/L3 判读只能来自按 §3/§4 预注册执行的采数轮(L1 的 Spearman/hot 对照 + L3 逐类署名),且 L1 先行。

## 请裁定

下一步是否放行 Tier-1 采数执行(§3 L1 检验先行:L1 事件集构造 + Spearman + hot 对照;L1 出口后再跑 §4 L3 判据)?或你要求先审 v6 代码本身?
