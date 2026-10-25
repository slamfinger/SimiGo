# simigo-v2.2.0rc1-os-page-return-20261024 — 物理页归还的 OS 级证据

生成于 2026-10-24T14:30+0800。本批次只做三件事：**物理页归还的 OS 级取证**、**GUI 前置条件复核**、
**逐层 `forward_calls` 的现状确认**。它不重跑任何已通过的契约测试，不修改 Service/HTTP 门的判定，
不触碰任何封存的 RC1/G2 证据。

---

## 1. 结论

| 事项 | 本批次判定 | 依据 |
| --- | --- | --- |
| 物理页归还（`physical_page_return`） | **PASS**（os3，脚本派生） | `evidence/os_page_return_verdict_os3.json`：A1–A9 全为 true |
| 产品 GUI 普通提示 | **BLOCKED_PREREQUISITE** | `evidence/gui_preconditions.json`：`screencapture` 无法取帧 |
| 逐层 `forward_calls` | **NOT_INSTRUMENTED** | 未插桩，未填任何估值（§7） |
| `v2.2.0rc1` 总体验收 | **仍 BLOCKED** | GUI 与 `forward_calls` 未闭合；见 §8 |

一句话：**这一次的结论不是"进程自己报内存降了"，而是内核自己的全局页计数器在进程仍然存活的情况下，
把该进程释放的 16.1 GiB 收回了 free 池**；同时压缩器没有吸收这些页（−0.02 GiB）、swap 基本没变（+1.18 MB），
退出 teardown 被单独测量并排除在外。

本批次**没有**修改 `simigo-v2.2.0rc1-local-acceptance-20261024/acceptance_report.json` 里的门记录。
原因与如何应用见 §8。

---

## 2. 被测量的对象（身份锚定）

本批次测量的是上一批次**已经安装、已经取证过**的那个候选二进制，没有重新构建，因此没有新身份：

| 项 | 值 |
| --- | --- |
| 候选 App | `~/SimiGo-Agent-Runs/simigo-v2.2.0rc1-service-http-20261024/install/SimiGo.app` |
| 可执行文件 SHA-256 | `60973e086f12583a20a6b578de33e678bd4a7e1846a7b6cd0084cd845eae90cd` |
| Bundle ID | `SwiftUI.SimiGo`（2.2.0 (26)） |
| 源码 HEAD | `f18d65f`（分支 `localb-b3-closure-20261016`），本批次未产生任何源码改动 |
| 模型 | `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`，snapshot `6e302ea604ad9ab206367e2c501d1571023e7b6d` |
| 机器 | 32 GiB 统一内存（`hw.memsize`），页大小 16384 B |

驱动的是**产品里已存在的、未修改的** headless 角色 `SIMIGO_HEADLESS_ROLE=memprobe`
（`SimiGo/Headless/SimiGoG1G3Entry.swift::memprobe`）：warm generate → 等满 240 s 生产自适应空闲下限 →
调用**未修改的** `runtime.suspendIfIdle()` → resume generate。没有计时间隙、没有从外部注入定时器、
没有从进程外直接调用任何释放接口。

每次运行都使用独立的隔离根（`runs/<rid>/{home,cache,state-graph,logs}`），
`SIMIGO_HOME` / `SIMIGO_CACHE_ROOT` / `SIMIGO_STATE_GRAPH_STORE` 全部指向该根，不接触真实用户状态。

---

## 3. 采样器测什么（`driver/run_os_page_return.py`）

三条独立的观测线，同一个 10 ms 时钟：

1. **内核全局页计数** — `host_statistics64(HOST_VM_INFO64)`，即 `vm_stat` 打印的同一组数。
   页只由内核记一次账，与进程自报无关。结构体按 SDK `mach/vm_statistics.h` 逐字段对齐；
   其中 `purgeable_count / speculative_count / compressor_page_count / throttled_count /
   external_page_count / internal_page_count` 是 `natural_t`（u32），其余是 u64。
   自测时若把这 6 个字段按 u64 读，会得到 1e15 量级的乱码；修正后与 `vm_stat` 逐项一致
   （compressor 43192、`total_uncompressed_pages_in_compressor` 91660、`throttled_count` 0）。
   另外：`free_count` 已经包含 speculative 页，因此"可用池"按 `free + inactive` 计，不再重复加 speculative。
2. **目标进程的内核记账** — `proc_pid_rusage(pid, RUSAGE_INFO_V4)` 的 `ri_wired_size` /
   `ri_resident_size` / `ri_phys_footprint`（偏移 56/64/72，uuid 占前 16 字节）。
   用一次 2 GiB 已知分配校验过偏移：resident 2151415808、footprint 2151532296，
   与 `ps` RSS 2100960 KiB 一致。
3. **存活探针** — 每个样本都做 `os.kill(pid, 0)`；并用角色自己写的证据文件 mtime 作为
   "写入那一刻进程还活着"的证明（该文件只在 resume generate 之后写出）。

---

## 4. 三次运行，以及一次必须披露的方法学更正

| 运行 | 采样间隔 / 基线 | 样本 | 墙钟 | 退出码 | 判定 |
| --- | --- | --- | --- | --- | --- |
| os1 | 100 ms / 30 s | 2,711 | 258.9 s | 0 | BLOCKED（旧规则 R1–R9） |
| os2 | 10 ms / 20 s | 22,618 | 256.1 s | 0 | BLOCKED（旧规则 R1–R9） |
| os3 | 10 ms / 20 s | 22,479 | 255.0 s | 0 | **PASS（A1–A9）** |

### 4.1 os1 / os2 为什么被旧规则判 BLOCKED

旧规则用"**run 段里 footprint 最小的那个样本**"当谷底。os1 的谷底落在 `289,057 ms`、
os2 落在 `276,217 ms`，都是**序列的最后一个样本**；那里 footprint 归零、free 涨到 21 万页，
是进程退出的 teardown，而不是 suspend 的释放。于是：

- os1：`R4` 只数到 0.1 s 的"低平台"（退出一瞬间），`R5` 内核可用页只涨 3.2 GiB / 下降 16.26 GiB = 0.197 → 判负；
- os2：`R5` 内核可用页只涨 0.02 GiB = 0.001 → 判负。

两次都是**判定器选错了窗口**，不是产品没释放。这一点必须写清楚：如果我只把规则改到能过，
那就是在搬动门柱。

### 4.2 证据：那个谷底确实是退出 teardown

用 os2 的 `captured_at` 反推采样器起点，与 `runs/os2/memprobe_os2.json` 的 mtime 对比：
角色在 `14:07:39.858` 释放，证据文件在 `14:07:40.142` 写入——**相差 0.28 s**。
也就是说序列末尾那次 16 GiB 的 free 上涨发生在这 0.28 s 的退出路径上。
这一节之所以要写，是因为"进程退出"正是授权书明令禁止当作归还证明的东西。

### 4.3 更正后的规则（A1–A9）为什么不是放宽

新规则把窗口**锚定在产品自己记录的 suspend 事件**上（`reference_release.at_ms` + 基线时长），
而不是锚定"进程后来做了什么"：

| 规则 | 内容 |
| --- | --- |
| A1 | 产品记录到 `reference_release` → `resource_reclaim` → `lifecycle_suspend` |
| A2 | 锚点前 1 s 内 footprint ≥ 1 GiB 且每样本存活 |
| A3 | 观测窗内 footprint 降到峰值的 ≤ 30%，且降幅 ≥ 1 GiB |
| A4 | ≥ 20 个连续样本（10 ms 间隔）低于峰值一半 |
| A5 | 内核 `free+inactive` 在 settle 窗内的最大值比锚点涨 ≥ 降幅的 50% |
| A6 | compressor 增长 ≤ 降幅的 25%（收缩算通过并如实报告） |
| A7 | 观测窗内每个样本 `rusage` 成功，**且**证据文件写入时间晚于观测窗结束 |
| A8 | 基线期 `free+inactive` 摆动 ≤ 降幅的 10% |
| A9 | 应用自报降幅与内核实测降幅相差 ≤ 20% |

比旧规则**更严**的地方有三处：A3 的阈值从 30% 提到 70%；A7 增加了"窗口结束后仍在运行"的证明；
退出 teardown 被单独测量（`exit_teardown_free_gain_bytes`）并显式标记
`exit_teardown_used_for_verdict: false`。比旧规则**更松**的地方没有。

旧规则的判定文件（`evidence/os_page_return_verdict_os{1,2}.json`）与原始记录一并保留，
不覆盖、不删除——它们记录的是一次错误的窗口选择，这本身就是证据。

---

## 5. os3：物理页归还

### 5.1 判定（`evidence/os_page_return_verdict_os3.json`）

```
A1_shipped_suspend_observed        true    reference_release@250950ms, resource_reclaim@250982ms,
                                           lifecycle_suspend@250982ms
A2_loaded_state_before_anchor      true    footprint 16.178 GiB @ anchor
A3_resident_set_fell               true    17,299,238,624 B 降幅 = 16.11 GiB（99.6% of peak）
A4_low_state_sustained             true    89 连续样本 = 0.89 s（阈值 20 样本）
A5_kernel_returned_the_pages       true    +8.19 GiB = 0.508 × 降幅
A6_compressor_not_the_sink         true    compressor −24,133,632 B（−0.02 GiB）
A7_process_alive_and_not_exiting   true    观测窗内 122/122 样本 rusage ok；
                                           证据写入 1792822485807 > 窗口结束 1792822483124（晚 2.68 s）
A8_noise_floor_small               true    基线摆动 159,989,760 B = 0.9% of 降幅
A9_app_and_kernel_agree            true    应用 17,345,900,232 B vs 内核 17,299,238,624 B（差 0.27%）
verdict = PASS   contradictions = []
```

### 5.2 内核侧究竟发生了什么

锚点（序列 `270,950 ms`，墙钟 `1792822481624`，`alive=1`、`rusage_ok=1`）与 `+490 ms`
（`271,440 ms`）两个样本：

| 计数器 | 锚点 | +490 ms | 变化 |
| --- | --- | --- | --- |
| `free` | 13,149 页（0.20 GiB） | 1,066,994 页（16.29 GiB） | **+1,053,845 页 = +16.08 GiB** |
| `inactive` | 898,741 页（13.72 GiB） | 381,616 页（5.83 GiB） | −7.89 GiB |
| `active` | 894,253 页（13.65 GiB） | 360,068 页（5.50 GiB） | −8.15 GiB |
| `wire_count` | 174,608 页 | 173,546 页 | −0.02 GiB |
| `compressor_page_count` | 63,267 页（0.97 GiB） | 61,794 页（0.94 GiB） | **−0.02 GiB（没有吸收）** |
| 目标 footprint | 16.178 GiB | 0.067 GiB | −16.11 GiB |
| `alive` / `rusage_ok` | 1 / 1 | 1 / 1 | 全程存活 |
| swap used（全程采样，非窗口对齐） | 3.731 GB（启动前） | 3.732 GB（结束后） | +1.18 MB / +0.03% |

读法：该进程在锚点时刻的 16.18 GiB 脏页记在 `active/inactive` 里；释放之后
**`free` 池正好涨了 16.08 GiB，而 `active+inactive` 正好少了 16.04 GiB**，两者相差 0.04 GiB（0.25%）。
这不是"进程说它小了"，是内核把这一批页从持有者名下收进了自己的空闲池；
压缩器没有接盘（−0.02 GiB），swap 基本没变（+1.18 MB / +0.03%），wired 没有接盘（−0.02 GiB）。

### 5.3 关于 A5 的 0.508，必须说明的测量口径

A5 用的是 `free+inactive`（内核可复用池总量），在锚点时刻这个口径**已经把该进程的 13.7 GiB
inactive 页算在内**，所以它天然低估释放带来的池增量：真实增量被"inactive 同时减少 7.89 GiB"抵消掉一半。
0.508 只是刚过 50% 线，结论**不建立在这个比值之上**，而建立在 5.2 的 free / `active+inactive` 对偶
（16.08 vs 16.04 GiB）+ A9 的 0.27% 一致性 + A6/A7 的排除项之上。写下这条口径披露，是为了让复核者
知道 0.508 为什么看起来偏低；阈值仍是 50%，没有改。

### 5.4 这不是关机、不是换进程

锚点后 4.19 s（`275,136 ms`）footprint 重新升到 **16.27 GiB**，`free` 回落到最低 3,990 页——
角色在 resume 之后重新分配了模型。同一 pid、`exit_code=0`、墙钟 255.0 s。
若把最后 1 s 的退出 teardown 也算进来，free 会再涨 15.66 GiB；这一项已单独记录且**不计入判定**。

---

## 6. GUI：仍阻塞，且没有被冒充

`evidence/gui_preconditions.json`（2026-10-24T13:56:02）：

| 前置条件 | 结果 | 可用 |
| --- | --- | --- |
| 屏幕录制（`screencapture -x`） | rc=1，stderr `could not create image from display`，未写出文件 | **否** |
| 辅助功能（System Events 读进程名） | rc=0，返回 `loginwindow`，无 1743 拒绝 | 是 |
| 前台进程 | `Qoder CN`（不是 loginwindow，不是锁屏） | 是 |
| 会话可交互 | `stat -f %Su /dev/console` = `mr.simi`；`who` 有 console 会话 | 是 |
| 候选身份 | 上述 App 存在，exe SHA-256 `60973e08…` | 是 |

判定 `BLOCKED_PREREQUISITE`，唯一 blocker 是 `screen_capture`。**本批次没有做、也不声称做过**：

1. 没有用 AX 驱动失败解释成"产品 GUI 已通过"；
2. 没有用 headless 生成代替用户操作；
3. 没有在没有截图的情况下描述"界面显示了什么"。

GUI 的解除条件不变：本机授予屏幕录制（与辅助功能）后，在实际安装的这个候选 App 里走完一次
普通用户操作，并同时采集进程身份、操作结果、生成日志与隔离根差分。

---

## 7. 逐层 `forward_calls`：仍然 NOT_INSTRUMENTED

未插桩，因此**没有**、也不会填入任何估算的调用次数。要闭合它需要在 vendored 依赖里加真实计数点，
那会产生新的源码改动、新构建与新身份，并与本批次已锚定的 `60973e08…` 脱钩——属于另一轮工作。

---

## 8. 与验收台账的关系（刻意没有做的事）

`simigo-v2.2.0rc1-local-acceptance-20261024/acceptance_report.json` 里
`physical_page_return` 仍写着 BLOCKED（`os_level_page_return_evidence: false`）。
本批次**没有**改它，也没有改它的生成器：那是 v2.2.0rc1 的门计数台账，
把它从 `12 PASS / 3 BLOCKED / 0 FAIL / 1 NOT_INSTRUMENTED` 改成 `13 / 2 / 0 / 1`
属于改变门计数，不在本批授权内。

替代做法：本批次写了一份机器可读的门附加件
`evidence/physical_page_return_gate_addendum.json`，指向 os3 的判定文件与原始记录、
候选身份、以及 9 条规则的逐条结果。若后续授权把这一项并入台账，正确路径是**让生成器吃这份附加件
并重新生成、重跑验证器**，而不是手改 JSON。

---

## 9. 边界

1. 未 push、未 merge、未创建 tag。
2. 未修改任何封存的 RC1/G2 证据，未修改旧批次的 `REPORT.md` / 原始日志 / 原始快照。
3. 未把 Service/HTTP 门的状态写入本批次，也未因本批次而改变它；两者互不覆盖。
4. 未修改产品源码，因此候选身份仍是 `60973e08…`；本批次结论只对这个二进制成立。
5. 物理页归还的 PASS 是**单独判定**的，不带动 GUI、不带动 `forward_calls`，也不使 `v2.2.0rc1`
   整体转为 PASS。

---

## 10. 复现

```bash
B=~/SimiGo-Agent-Runs/simigo-v2.2.0rc1-os-page-return-20261024
cd $B
# 1) GUI 前置条件（只读探针，不推进任何门）
python3 driver/probe_gui_preconditions.py

# 2) OS 级采样（每轮独立隔离根；耗时约 4.5 分钟）
OS_PROBE_INTERVAL=0.01 OS_PROBE_BASELINE=20 python3 driver/run_os_page_return.py os3
cp evidence/os_page_return_raw.json evidence/os_page_return_raw_os3.json

# 3) 判定（脚本派生，不手写任何数字）
python3 driver/verify_os_page_return.py \
    evidence/os_page_return_raw_os3.json evidence/os_page_return_verdict_os3.json 20 1500
echo $?   # 0 PASS / 2 BLOCKED / 1 矛盾证据

# 4) 索引与清单
python3 driver/make_evidence_index.py
python3 driver/make_manifest.py .
sh driver/verify_manifest.sh
```

---

## 11. 清单

`MANIFEST_SHA256.txt` 覆盖本批次除自身与 `logs/manifest.log`、`logs/verify_manifest.log`
之外的全部保留文件（含三次运行的原始记录、隔离根里的 memprobe 证据与 sqlite/keychain 残留，
即"隔离根确实被使用"的旁证）。`EVIDENCE_INDEX.md` 的 A 段是"结论 → 文件 → 该看哪个字段"的映射，
B 段是逐文件字节数与 SHA-256。`default.profraw` 是启动产品二进制时产生的 0 字节 LLVM 覆盖率占位文件，
保留但无证据价值，与上一批次处理一致。
