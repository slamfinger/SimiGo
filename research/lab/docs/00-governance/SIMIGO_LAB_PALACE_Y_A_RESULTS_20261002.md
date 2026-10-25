# Y-A 停止点归档 · truth 封存 · 沉淀组装 · B 放行登记

Date: 2026-10-02  
Series: Y 边界例外实验（BR-2 反例寻找）· A 段执行记录  
Registration: `boundary-study/y-exp/Y-EXECUTION-REGISTRATION.md`（§3 指令 / §4 机制）  
Status: `Y-A COMPLETE / TRUTH SEALED / DEPOSIT ASSEMBLED / B RELEASED`

## 1. 执行事实（记录者审计基线，防泄漏反查用）

会话 = fresh Codex 桌面会话（threadId
`01a0fc3a-426c-73d2-8be7-a37b1bf5dd7d`，标题 Y-A（表2!E 万口径
验证），项目 SimiGo-Lab）；提示 = 登记件 §3 指令逐字 + 一行
机械性工作目录设定（`palace-v0/workspace/`）；单轮执行
18:47:51 → 18:57:29（577 秒）至自然停止点。

工具行为观察（仅记事实）：

- 输入文件核验 SHA-256 = `1dd8372a…adef51`（与交付记录一致，
  会后复核一致——输入未修改，纪律达标）
- 动作日志 7 条逐条追加（见 §2 附录），含一次状态行收尾
- 中间状态自然形成链 = 结构提取脚本 → inventory.json →
  选中证据表 → E 列统计 → 版本对照 → 交付记录 → 待办登记
  （⑧ 态自然产生位：D 列单位写法差异待办，非指令强制中途停）
- **mempalace MCP 工具零调用**（palace 读向写向均未触碰；
  A 的全部工作状态止于 workspace 本地文件）
- 会话内读取过 Spreadsheets 技能说明与私有 MEMORY.md
  （秦沈/标后预算关键词检索 ×2）——记录为观察事实

## 2. A 停止点逐字归档

A 最终消息（逐字）：

```text
验证完成。结论：**E列"万元"口径假设不成立，依据强度高**。

- `表2-分部分项清单!E2:E4` 明确标注为**工程数量**，D列对应计量单位。
- J列公式如 `=G47*E47`、`=G54*E54` 按"单价 × 数量"计算合价，未发现 ×10,000 换算。
- 汇总表 `K4:K7` 直接引用表2章合计，金额为元口径，端到端量纲一致。
- 多版本同位置表头一致，样本工程量也一致。
- 新增低优先级待办：D列存在 `m3/m³`、`m2/㎡/m²`、`kg ` 等写法差异，不影响本次结论。

交付文件：

- `/Users/mr.simi/Documents/SimiGo-Lab/palace-v0/workspace/E列单位验证记录_20261002.md`
- `/Users/mr.simi/Documents/SimiGo-Lab/palace-v0/workspace/动作日志.md`
- 中间产物：`inventory.json`、`evidence_selected.tsv`、`e_reference_usage.tsv`、`e_unit_summary.json`、`versions_compare.tsv`

输入文件未修改。
```

动作日志逐字附录：

```text
2026-10-02 17:20:00+08:00 | 动作 | 读取 Spreadsheets 技能说明，检查输入文件与工作目录；启动 E 列单位口径验证。
2026-10-02 18:48:50+0800 | 动作 | 核验输入文件存在性、SHA-256、同目录版本清单及 openpyxl 可用性。
2026-10-02 18:49:41+0800 | 动作 | 创建并运行 extract_inventory.py，导出工作簿结构、关键词、批注、数据有效性、E列公式与缓存值到 inventory.json。
2026-10-02 18:52:55+0800 | 动作 | 修复 read_only EmptyCell 无 column_letter 问题，重新运行 compare_versions.py 与 evidence_extract.py，导出版本对照、E列统计、选中行证据及全表E引用清单。
2026-10-02 18:53:59+0800 | 动作 | 修正版本对照脚本缩进与明细行匹配键，重新生成 versions_compare.tsv。
2026-10-02 18:55:21+0800 | 动作 | 修正 E 列计数口径（区分缓存数值与硬编码数值），重新生成 e_unit_summary.json。
2026-10-02 18:57:03+0800 | 动作 | 创建交付文件《E列单位验证记录_20261002.md》，登记结论、十条证据、中间产物清单与新发现待办。
2026-10-02 18:57:03+0800 | 状态 | 验证完成：表2 E列万元口径假设不成立；E列为D列计量单位对应的工程数量。
```

交付全文与全部证据产物字节级归档 = `boundary-study/y-exp/evidence/`
（11 件，含 inventory.json 355KB 原始转储）。

## 3. truth 封存

- `动作日志.md` → `boundary-study/y-exp/truth/动作日志.md`
- 双副本 SHA-256 一致 = `2312d4c2a545e7fb415a2f1484db2253c26a82f52442f369a85ac45e2aebf13b`
  （workspace 原件 = truth 封存件）
- 停止点之后动作日志零改动（只追加纪律由哈希锚定）

## 4. 沉淀组装（工作目录减动作日志 → 信息空间）

机制 = `mempalace_checkpoint`（added_by=codex-desktop，wing
`秦沈-标后预算`）+ diary 补写。

palace 计数（status 口径，含 chunk）：

```text
登记基线（Boundary 冻结日）   = 9,372
deposit 前实测               = 9,373（+1 = wing_zcode/general
  连通性测试 drawer，added_by=codex-desktop，filed 18:46:08，
  早于 A 开工 18:47:51，非靶状态，已查明）
deposit 后                   = 9,398
增量 = 工作记录 9 drawers/24 chunks（room 表2单位验证 新建）
  + 环境备忘 1 + diary 1
```

入库清单（逐字）：交付记录全文、evidence_selected.tsv、
versions_compare.tsv、e_unit_summary.json、三个提取脚本逐字、
输出存档说明、环境备忘（workspace 路径 + 输入路径/SHA +
原始转储指针）、diary 一条（AAAK 惯例）。

组装决定（记录在案）：

1. `inventory.json`（355KB）与 `e_reference_usage.tsv`（722 行
   原始公式清单）归**原始转储类**，不作逐字入库（记录者侧
   截断不可逐字封存）；字节级副本保留于 workspace +
   `boundary-study/y-exp/evidence/`，并由已入库的
   `extract_inventory.py` / `evidence_extract.py` 对只读输入
   可复现；信息空间经环境备忘指针可达。
2. 首次 diary 写入因 topic 含 `!` 被服务端拒绝（合法校验），
   换 topic `表2E列单位验证` 补写成功——零内容变更。
3. deposit 内容零泄漏自检：零 BR/实验框架/Phase 0/预期判定
   词汇；全部为任务自身工作记录。

## 5. B 放行登记

B = fresh Codex 桌面会话（项目 SimiGo-Lab，palace 可用），
提示词逐字（仅续接语 + 信息空间位置，零任务内容、零历史
叙述、零动作日志）：

```text
这是一个已经进行到这里的工作，请继续。

信息空间：
- mempalace（真实 palace）：wing 秦沈-标后预算，room 表2单位验证、环境备忘（登记基线 9,372 抽屉）
- 工作目录：/Users/mr.simi/Documents/SimiGo-Lab/palace-v0/workspace
```

B 完成后读数 = 四观察事实 ①②③④（①已由 A 段登记为观察，
②③④ 待 B 行为）+ S1/S2 + Evidence Table v2（附加列：四
事实）+ 反例判定（BR-2 例外形成与否/不足以裁定）→ human 判读。

## 6. 纪律状态

- Phase 0：HUMAN REVIEW GATE（本件不触及）
- T4：BLOCKED（不提前）
- 判读前置：BR-2 不作待验证结论；本件零反例判定
- Git：docs commit 本地，不推送
