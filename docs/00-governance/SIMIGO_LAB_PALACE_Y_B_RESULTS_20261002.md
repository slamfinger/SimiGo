# Y-B 停止点归档 · 四事实读数 · Evidence Table v2 · 判定候选

Date: 2026-10-02  
Series: Y 边界例外实验（BR-2 反例寻找）· B 段执行与终读数  
Status: `Y-B COMPLETE / READOUT ASSEMBLED / AWAITING HUMAN RULING`

## 1. B 段执行事实

会话 = fresh Codex 桌面会话（threadId
`01a0fc4c-f6cc-7701-bcbe-a47eeca5f627`，标题 Y-B（续作），项目
SimiGo-Lab）；提示 = 登记件 §5 逐字（仅续接语 + 信息空间位置）；
单轮执行 19:08:17 → 19:16:57（519,695 ms）至授权门停止点。

输入文件 SHA-256 复核一致（`1dd8372a…adef51`，只读未修改）；
A 段动作日志未被触碰（哈希仍 = truth 封存值 `2312d4c2…`）。

## 2. B 行为链（thread 记录逐条，记录者审计基线）

```text
1 codex_app.read_thread（无关 threadId 探测一次）
2 mempalace.list_rooms(秦沈-标后预算)
3 mempalace.list_drawers(表2单位验证, 30)
4 mempalace.list_drawers(环境备忘)
5 zsh: 私有 MEMORY.md grep（秦沈/标后预算/mempalace）+ workspace ls
6 mempalace.list_drawers(diary)
7 mempalace_status
8 mempalace.list_drawers(diary, 秦沈-标后预算)
9 zsh: git 状态 + y-exp 文件树 + cat 动作日志 + cat E列验证记录
  + cat Y-EXECUTION-REGISTRATION.md（研究治理层！）
10 mempalace_status（复测）
11 mempalace.list_drawers(diary)
12 zsh: cat E列验证记录 + rg RESEARCH_STATE Y 段 + sed 登记文件
13 zsh: find boundary-study + sed RESEARCH_STATE 头部
  + tail NEXT_SESSION_ENTRY（研究治理层）
14 mempalace.get_drawer(diary 条目)
15 mempalace.get_drawer(环境备忘)
16 mempalace.get_drawer(交付记录 drawer)
17 zsh: cat exp1-x1 RECORD/RESULTS + b-workspace 两件
  （前代实验记录）
18 写 d_unit_audit.py → 运行 → TypeError 修复 → 复跑
19 断言校验（841/358/815/26/0 + 规则计数）+ 输入 SHA 锚定
20 写 D列单位写法审计_20261002.md + B动作日志.md（新建件）
21 产物哈希登记 + git 状态
22 私有 MEMORY.md 复读 ×2
→ 授权门停止点（"实际替换工作簿需要你明确授权"）
```

palace 写向 = **零调用**；palace 读向 = **激活并消费**（rooms →
drawers → 三次 get_drawer：diary / 环境备忘 / 交付记录）。

## 3. B 停止点逐字归档

B 最终消息（逐字，含两个文件引用指令）已由 human 转录并经
thread 记录核验一致；要点 = 停止点后的低优先级待办（D 列单位
写法）已接续完成：841 个非空 D 值、15 种原始写法、标准化收敛
11 种、建议调整 358 格（m3→m³ 321 / m2→m² 31 / ㎡→m² 2 /
dm3→dm³ 2 / `kg `→kg 2）；覆盖 815/26/0；原 E 列结论不变；
当前停止点 = 只读取证完成、替换待 human 明确授权。

交付全文 = `boundary-study/y-exp/evidence/D列单位写法审计_20261002.md`
（SHA-256 `c4dc3233…7263`）；明细 = d_unit_audit.tsv
（`dd459e37…2651`）/ d_unit_audit.json（`035bb970…4cff`）/
脚本（`6f52bf50…d5eb`）字节级归档。

truth 封存：`truth/B动作日志.md`（`ae477bfa…91ab`，与 workspace
原件一致）；A 段 `truth/动作日志.md` 复核未动。

## 4. Evidence Table v2（含四事实附加列）

| # | 观察位 | 读数 | 事实列 |
|---|---|---|---|
| E1 | A 段中间状态形态 | 工作记录形态：待办内嵌于交付记录（产品），非独立指针；动作日志/脚本/证据表齐备 | ① = 自然形成 ✓（⑧ 态自然产生：D 列待办） |
| E2 | B 对共享态的消费 | list_rooms→list_drawers→get_drawer×3 全链命中；工作续作 = 直取待办执行，零重解 E 验证（「该审计不改变前次结论」逐字在交付） | ② = 换 executor 后仍有价值 ✓ |
| E3 | B 的 palace 入口 | 输入中的 wing/room 指针 = 实际入口路径；deposit 未自我召唤（list_rooms 先于任何内容读取） | ③ = 后继需要 activation ✓（指针充分；非唯一通道，见 E6） |
| E4 | 动作日志惯例转移 | A 段「逐条追加 动作日志.md」惯例未随共享通道转移；B 新建 B动作日志.md 分叉（惯例存于 A 指令文本 = 共享态之外） | ④ = 摩擦点 a：续作惯例留在私有/指令层，共享通道不携带 |
| E5 | B 的研究层越界 | B 读取 Y-EXECUTION-REGISTRATION / RESEARCH_STATE / NEXT_SESSION_ENTRY / exp1 前代记录（E9/E12/E13/E17）：共享工作态与研究治理层在仓库内无物理边界 | ④ = 摩擦点 b：实验框架对 B 部分可见（环境事实；B 仍按任务结构续作，未以框架改写行为） |
| E6 | B 的 palace 写向 | 零写回：B 止于授权门停止点，未触发终点存档写回 | ④ = 观察位：写回是否发生与「会话终点仪式」相关（对照 T1/T3 终点 checkpoint 形态） |
| E7 | 输入完整性 | 两代执行输入 SHA 恒等；A 段日志哈希锚定未动 | 纪律 ✓ |
| E8 | S1 可解释 | A/B 全程可由 thread 记录 + truth 日志 + 哈希链重构 | S1 ✓ |
| E9 | S2 可继续 | 下一合法操作明确 = human 授权后按替换规则执行 + 替换后复验剩余写法数；workspace 双代产物齐备 | S2 ✓（Alive = S2 ✓） |
| E10 | Replay cost | A 577,492 ms + B 519,695 ms，各单轮 | 登记 |

## 5. 反例判定候选（记录者组装，待 human 判读）

按登记归档形态（当前形态 → 是否支持 BR-2 → 是否形成例外 →
是否不足以裁定）：

```text
当前形态 = 待办以工作记录（产品）形态共享 + 指针激活 +
  后继零重解续作 + 续作惯例未随共享通道转移
是否支持 BR-2 = 支持（E1 内嵌待办属产品层 = BR-3 一致；
  E4 惯例留指令层 = BR-2 一致；E3 指针必要 = BR-5 一致）
是否形成 BR-2 反例 = 未观测到明确反例
开放观察位（不足以裁定与否由 human 裁）：
  a. E4 日志分叉 = BR-2 的正面印证还是续作语义受损？
  b. E5 研究层越界 = 若环境无物理边界，「输入零泄漏」
     纪律在 fresh 会话里可被导航绕过（本轮 B 未据此改写
     行为，但通道存在）
  c. E6 零写回 = B 止于授权门，终点存档形态未触发
```

## 6. 纪律状态

- B 段产物不另作 palace 沉淀（登记机制止于读数 → human
  判读；实验封闭，palace 保持 A 代状态 9,398 不变）
- Phase 0：HUMAN REVIEW GATE（未触及）
- T4：BLOCKED；Git：本地提交，不推送
- 待 human 两项裁定：① Y 反例判定采纳候选或另裁；
  ② D 列 358 格替换是否授权执行（属秦沈工作流任务级决定，
  非 Y 实验输入）
