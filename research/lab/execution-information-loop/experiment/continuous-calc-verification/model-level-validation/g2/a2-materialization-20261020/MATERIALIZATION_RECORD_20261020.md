# A2 制品物化验证（离线，2026-10-20）

**状态：`PASSED — OFFLINE ONLY`。未加载模型，未消耗任何 P0 授权，不是 P0 运行事实。**

本记录执行的是裁定中的 A2 路径离线部分：把符号链接 snapshot 物化为普通文件副本，并核验副本与冻结 binding 的内容同一性。它不修改读取器，也不声称 `EngineModelIdentity.compute` 已支持 Hugging Face 的符号链接布局。

## 1. 裁定依据

| 选项 | 裁定 |
| --- | --- |
| A1 收窄内容绑定定义 | 不采纳为 G2 方案 |
| A2 物化解引用副本 | 采纳，先离线验证（本记录） |
| A3 修正 `EngineModelIdentity` | 暂不实施，另开工程门 |

原 P0 `FAIL`（run `20261020T072607Z`）原样保留，未覆盖、未改判、未追认。

## 2. 物化对象

| 项 | 值 |
| --- | --- |
| 源目录 | `~/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots/6e302ea604ad9ab206367e2c501d1571023e7b6d` |
| 源形态 | 17 个条目，全部为符号链接（指向 `../../blobs/…`） |
| 副本目录 | `…/g2/artifact-model-qwen3-coder-30b-a3b-instruct-4bit-6e302ea6` |
| 副本形态 | 17 个条目，全部为普通文件，0 个符号链接 |
| 命令 | `mkdir -p "$DST" && cp -RL "$SRC"/. "$DST"/` |
| 耗时 | 11.7 s（APFS，未单独插桩是否走写时复制 extent 共享） |
| 占用 | 16,794,104 KiB（含目录元数据）；binding 记录的字节总和为 17,197,118,924 |
| inode | 副本与源 blob 为不同 inode，link count 均为 1（示例：`config.json` 副本 109136892 / 源 96200789） |
| 版本控制 | 副本目录被 `.gitignore` 排除，不入库；删除副本是另一件独立的事 |

## 3. 核验结果

脚本：`a2-materialization-20261020/check_materialization.py`，`SCRIPT_VERSION = 2`；输出 `materialization_check.json`（schema `SIMIGO-G2-A2-MATERIALIZATION-CHECK-V1`）。

| 检查 | 结果 |
| --- | --- |
| 冻结清单文件数 == 副本条目数 | true（17 == 17） |
| 无遗漏路径 | true |
| 无新增路径 | true |
| 全部为普通文件（无符号链接） | true |
| 逐文件字节数与 SHA-256 全部匹配 | true（17/17） |
| 聚合摘要匹配 binding | true |
| 源目录确为符号链接 snapshot | true |

重新计算的聚合摘要：

```
4c1bd7596b9480864ca7c5ac949fbb051c47b182b853a8219c80a171b22f6678
```

与 `SIMIGO-G2-MODEL-BINDING-V1` 一致。路径集合、字节数、逐文件摘要三者共同排除了静默增加、遗漏与重命名。

## 4. 规则复算（预测值，不是引擎读数）

对副本运行 `p0/diagnostics/identity_enumeration_probe.swift`（复刻 `EngineModelIdentity.compute` 的枚举与拼接规则，不载模型），输出 `enumeration_rule_replica.json`：

| 项 | 值 |
| --- | --- |
| 枚举条目数 | 17 |
| `isRegularFile == true` | 17 |
| `isSymbolicLink == true` | 0 |
| weights 行数 | 4 |
| weights 摘要 | `d1f01c0c98db2d07a437e81372dffc49c04e728342cec8f72cc2929caeeb6abf` |
| tokenizer 参与字节 | 4,461,426 |
| tokenizer 摘要 | `9bada7c8fddefc7e91cf3bbe9b56305d5234c73e16732518dc4f3825b2d84ac3` |
| 若两项均如上，namespace 指纹预测 | `bb0b2711451cbabc1efc0aae3e282dde166db6f0e82ba245905b4848bf71ec58` |

**这些是规则复刻的输出，不是 `EngineModelIdentity` 的返回值。** 冻结 P0 的失败恰恰说明"规则说得通"与"引擎实际算出什么"是两件事：上一轮在源目录上，规则复刻预测 `d1f01c0c…`，引擎给出 `e3b0c442…`。因此本节的数字只能作为下一次 P0 的对照预期，不能替代它。

tokenizer 摘要依赖 `FileManager` 的枚举顺序，不由 binding 决定，也不是可独立复算的目标值；下一次 P0 只应以 weights 摘要与聚合为门槛，tokenizer 摘要按实际记录。

## 5. 本记录不确立什么

- 不证明引擎会为副本计算非空或匹配的身份。引擎是否跟随/跳过普通文件，仍未观测。
- 不证明副本能在目标宿主上加载、渲染或生成；本轮没有启动模型。
- 不证明缓存挂钩在副本上可用；上一轮的 `calls=1 / hits=0` 只对源目录成立。
- 不构成新的 P0 记录，也不能把原 P0 的 `FAIL` 追认成通过。
- 不解决任何 G2-A / G2-B / G2-C 结论；批次仍未授权。
- 不修复 `EngineModelIdentity.compute` 的符号链接缺陷（A3 仍是独立议题）。

## 6. 设计后果

副本目录的最后一段路径 `artifact-model-qwen3-coder-30b-a3b-instruct-4bit-6e302ea6` 将成为引擎身份中的 `modelID` 分量（源目录该分量为 revision `6e302ea6…`）。因此换用副本后：

- 内容分量首次真正参与 namespace：不再是常量 `188a16c59bd1407be74e57c04e46e20b7dd9f54b2582d91391d0b01d727c0938`；
- `modelID` 分量改变，即便内容分量仍为空，副本的 namespace 也不会与源目录相同——这是刻意保留的，避免两次运行撞进同一 store；
- 目录名须视为执行条件的一部分，随 P0 补充记录一起冻结，不得在运行时改名。

副本的 mtime 与源不同，因此 `modelDirectoryRevision`（元数据栅栏）的取值也会变。该栅栏只要求一次运行内自洽，不要求跨目录相等。

## 7. 版本与偏差披露

- `check_materialization.py` v1 在加入 home 前缀脱敏（`/Users/<user>` → `~`）之前跑过一次；该输出在发布前被丢弃，从未入库。加入脱敏后版本号升到 v2 并重新运行一次。v1 与 v2 的检查项、聚合摘要、逐文件结论与预测值完全相同，只有显示路径不同——哈希计算用的是真实路径，脱敏只作用于写进记录的字符串。
- `p0/diagnostics/identity_enumeration_probe.swift` 同步加入了 `root` 字段脱敏。该脚本在 `4401a38f` 中已入库的旧输出保持原样，属于历史记录，不回改。
- 本轮未修改 `simigo2-experimental` 任何源文件与 `Package.swift`，未触碰 G1 `CLOSED`、Frozen Contracts、Carrier、signer。

## 8. 复现

```sh
cd execution-information-loop/experiment/continuous-calc-verification/model-level-validation/g2
python3 a2-materialization-20261020/check_materialization.py \
  --binding ~/Documents/SimiGo-Lab/docs/01-questions/G2_MODEL_BINDING_20261020.json \
  --source ~/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots/6e302ea604ad9ab206367e2c501d1571023e7b6d \
  --dest artifact-model-qwen3-coder-30b-a3b-instruct-4bit-6e302ea6 \
  --out /tmp/materialization_check.json
```

脚本只读源与副本，输出以 `O_EXCL` 创建；不带 `--force`，不覆盖既有记录。

## 9. 下一步（未执行）

1. 起草并冻结 P0 补充记录：新的 `model_dir`、相同聚合、变化原因、未变化项。
2. 取得**新的显式 P0 授权**（一次启动、无重试）后，才可加载副本。
3. 在此之前不加载副本、不签发 G2 批次 manifest、不推送本地提交。
