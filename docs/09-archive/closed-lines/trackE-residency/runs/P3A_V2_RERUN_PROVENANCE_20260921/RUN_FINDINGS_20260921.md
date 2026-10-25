# P3-A v2 重跑 Provenance 闭合 + 一处 stale 数字修正(2026-09-21)

> 目的:闭合外审对 `301e3f1` 的两个剩余审计项——① v2 重跑数字的
> commit 级 provenance;② lfu_aging 策略身份/结果标签一致性。
> 方法:在被审计代码原样(HEAD=301e3f1,tree clean)上实际执行,
> 全量产物入档本目录;另做 decay ON/OFF 对照实验钉死数字来源。

## 1. 执行环境(PROVENANCE_META.txt 同步记录)

- git HEAD:`301e3f1ec766d237e91d8698b84530c62c9d3833`(即被审计 commit)
- 工作区:tracked 文件零改动(`git status --porcelain` 仅本目录 untracked)
- simulator sha256:`5dbc8cc04ac419782cd03ee6afbe59a74a759d1840d81f818510c6aed2015375`
- Python 3.14.5;命令:`python3 trackE-residency/residency_policy_simulator_v3.py`(cwd=仓根)
- 时间:2026-09-21T14:15:54Z;退出码 0;确定性自检 PASS
- stdout 全文:`V2_RERUN_STDOUT_301e3f1.txt`

## 2. 实跑结果 vs 301e3f1 文档 v2 表(逐格核对)

| 格 | 文档 | 实跑 | 判定 |
|---|---|---|---|
| hot/lru | 973.1 | 973.1(rehy 696/ext 684) | 一致 |
| hot/lfu_aging | 544.4 | 544.4(rehy 392/ext 380) | 一致 |
| hot/cost_aware(H=8) | 547.3 | 547.3(rehy 394/ext 382) | 一致 |
| hot/belady | 475.3 | 475.3(rehy 343/ext 331) | 一致 |
| tree/lru | 1422.9 | 1422.9(rehy 1015/ext 1003) | 一致 |
| **tree/lfu_aging** | **1084.5(−23.8%)** | **1085.9(−23.7%)(rehy 776/ext 764)** | **不一致,见 §3** |
| tree/cost_aware(H=8) | 1156.4 | 1156.4(rehy 826/ext 814) | 一致 |
| tree/belady | 740.4 | 740.4(rehy 531/ext 519) | 一致 |
| H=4/8/16(hot,cag) | 815.2/547.3/547.3 | 815.2(rehy 584)/547.3/547.3 | 一致 |
| pressure_raw 全通道 | ≈1983–1991 | 1983–1991(k_c 9/10/11 × hot/tree × 3 策略) | 一致 |

## 3. 实质发现:tree/lfu_aging 文档数字为 pre-decay 语义残留(stale)

外审预警的模式**被证实**:lfu_aging 在 `301e3f1` 中补入真 aging
(每 200 步 freq //= 2)后,文档 v2 表的 tree 格仍写 1084.5——与
ce5cdb0(pre-decay,cumulative-frequency 无衰减)的旧数字完全相同。
对照实验(`SIDECHECK_DECAY_OFF.txt`;仅运行时 patch
`LFU_DECAY_INTERVAL→10^18`,模拟器文件零改动,trace 按 main() 原
RNG 消费顺序复现):

- **decay OFF(pre-301e3f1 语义):tree/lfu_aging = 1084.5(rehy 775/ext 763)**——与文档数字逐位一致;
- **decay ON(301e3f1 语义):tree/lfu_aging = 1085.9(rehy 776/ext 764)**——恰一对 rehy+ext 之差(0.72+0.69=1.41),即 decay 恰好改变一个驱逐决策;
- hot 上 decay **决策中性**(两种语义均 544.4,rehy 392/ext 380)——这解释了为何 v1→v2 时该问题未暴露(唯一变化的格在 tree)。

**结论**:301e3f1 文档 v2 表的 tree/lfu_aging 格不是 301e3f1 代码
的产物,而是语义变更前的残留数字。已在 RESIDENCY_P3A_RESULTS 修正
为 **1085.9(−23.7% vs lru)**。影响评估:tree 排序不变
(lru 1422.9 > cag 1156.4 > lfu 1085.9 > belady 740.4),频率信号
结论与 cost_aware 判别均不翻转。

## 4. lfu_aging 策略身份澄清(审计项②)

现行语义 = **cumulative-frequency 计数底座 + 每 200 步频率半衰
(aging)**;驱逐 key = (freq, last_access, id),即频率主序、
LRU 次序破频率平局。文档标签已由 `cumulative-freq variant`(原意
"非真 aging"的旧注记,与补入 aging 后的代码语义冲突)改为
`cumulative-freq + 每200步半衰 aging`,消除歧义。

## 5. 附带修正(非 blocker)

文档 verdict 块原句 "H=4 仍 +15.8% 较差" 与 "+? 较差" 占位符:
实跑 H=4(hot)= 815.2,**vs lru = −16.2%(优于 lru)**,vs H=8
547.3 = **+49.0%(较差)**。"较差"仅在相对 H=8 时成立;
"+15.8%" 无任何实跑来源,一并清除。

## 6. 审计项闭合映射

| 外审审计项 | 状态 |
|---|---|
| ① v2 rerun provenance(commit 级) | **已闭合**:本目录全套产物(环境+stdout+对照实验),可在任意机器复现(同 Python 版本下逐位一致) |
| ② LFU 策略身份/结果标签 | **已闭合**:语义澄清 + 标签修正 + stale 格修正(1084.5→1085.9) |
| 非 blocker:H=4 占位符/+15.8% | **已修正**(vs lru −16.2% / vs H=8 +49.0%) |

P3-A 是否提升为 **PASS / Cost-aware 形态决策 UNLOCKED**,待审核方
对本套产物终判。
