# SimiGo v2.2.7 (2) 发布说明

## 一、版本

| 项 | 值 |
| --- | --- |
| 版本 / 构建号 | 2.2.7 / 2 |
| 版本性质 | 正式发布（同 2.2.7 的能力面，补三处「账要说清」的实现） |
| 分支 / 提交 | `main`；发布时以 tag 指向的提交为准 |
| 平台 | Apple Silicon macOS 26.4+ |
| 产物 | `SimiGo-v2.2.7-2-<exe8>.dmg`（exe8 为可执行文件 SHA-256 前八位） |
| 签名 | ad-hoc，未公证；首次打开需绕过 Gatekeeper |

本次构建的产物身份：`SimiGo-v2.2.7-2-0a6b308c.dmg`，
SHA-256 `1d136881649b5a781229491a752b48520243ff4003807c049b1a71a7e6e184f0`；
DMG 内 `SimiGo.app` 19 个文件，无 sqlite / jsonl / log。

产品是什么、三个权威边界、本版能力与安装要求，见 [v2.2.7 说明](RELEASE_NOTES_v2.2.7.md)。
本文件只写这个构建比上一个构建多出来的三件事。

## 二、归属失败不再只是一行日志

增量归属要在写事务里落 `space_turns`。全量重建或补录持锁时它会撞上 `SQLITE_BUSY`，
而此时摘要和关键词已经落库——用户看不见这一轮「素材进来了、没人认识它」。

现在：失败进 `space_assignment_retry`（同一轮重复失败只累计次数），进程重启后仍在；
启动时与每次摘要写入都重放一次，成功即删行；次数到 5 次为止不再重试，由
`abandoned` 报数，行不消失、可查。全量重建覆盖每条带摘要的轮次，收尾清空队列。

## 三、缺口多了一项：房间

设置页的缺口数从四项变五项，第五项是「有摘要、但没有任何房间归属的轮数」。它独立
于其余四项：归属写入失败时摘要已经落库，前四项一个都不变。口径排除「既无摘要也无
归属」的轮次——那种轮次由摘要项说话。说明见
[信息空间缺口账：四项 → 五项](../decisions/IS_GAP_LEDGER_20261113.md)。

## 四、补不上的那一轮，说得出为什么

补摘要/补关键词的回执不再只有「成 N 轮，败 M 轮」：每一轮失败都带
`session#turn` 与原因（格式不合 / HTTP：非 200 / HTTP：无 content / 写库）。让位与
停止不是失败，不计入失败数，单独报「让位 N 次、停止于哪一轮」。设置页显示前 8 条
明细，全量留在缺口账上。

## 五、证据状态（2026-11-13）

- CI `build: 2.2.7 (2)`（run 43340158005，head `a3598c7`）：9/9 成功，含 Runtime
  contract、macOS targeted、macOS P0/P1 HTTP/MCP、answer-reuse、LOCALB、
  transcript collection、release staging audit、release hygiene。
- 本机：Runtime contract 422/422（含新增 4 例）、Collection 221/221、
  LOCALBCore 58/58、App 目标 RequestAdmissionScheduler 10 例 + TurnDigestReceipt
  3 例全绿；`release_manifest.py check`、`release_artifact_audit.py`、DMG 内
  staging audit 均 PASS。

## 六、边界（这一版没有证明的）

- 重试只有**次数上限**，没有时间退避：触发点是启动与摘要写入，不是定时器。
- 让位（yielded）的计数进了回执，但**没有自动化回归**——真实引擎竞争造不出可重复的
  判据，只有字段连线与真实空窗行为承担。
- 已知补不上的那一轮（`qoder-712d17bd` 第 1 轮）在本次构建上**没有重跑补录**：
  现在它能留下原因，不代表它已经被补上。补不补得上下一次实测才知道。
- 打包为 ad-hoc 签名，未公证；也没有做安装版端到端回归（既有端到端记录见 v2.2.7 说明）。
