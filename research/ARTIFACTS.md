# research/_artifacts/ — 本地完整归档（不推送）

这三个目录是整合前的**原始目录整体移动**而来，保留全部文件、权限、`.git` 历史与未跟踪产物。
`research/_artifacts/` 被 `.gitignore` 排除，只存在于本地仓工作树，不会推送到 GitHub。

| 目录 | 文件数 | 体积 | 内容 |
| --- | ---: | ---: | --- |
| `SimiGo-Agent-Runs/` | 95,803 | 11 GB | 全部 agent 运行批次：报告、证据、构建产物、App、DMG、DerivedData、envtest 运行态 |
| `SimiGo-Lab-R01-Fixtures/` | 3,291 | 183 MB | 全部 R01 夹具，含 `prep/.build` 与 `recon/.build` |
| `SimiGo-Lab-repo/` | 129,206 | 12 GB | Lab 完整本地仓：`.git` 438 MB、`vendor/` 2.0 GB、`.transfer/` 2.4 GB、`.build/` 852 MB、`simigo2-experimental/` 6.5 GB |

## 与 Git 跟踪内容的关系

- `research/lab/`：Lab `main` 的全部受版本控制文件（tree 与 Lab 仓 `main` 完全相同）。
- `research/fixtures/r01/`：R01 的全部非构建文件。
- `research/agent-runs/`：Agent-Runs 的全部证据、报告、脚本、补丁与清单；构建产物、App/DMG、运行时 SQLite、密钥材料仅保留在本目录。

## 说明

- 原路径 `/Users/mr.simi/SimiGo-Agent-Runs`、`/Users/mr.simi/Documents/SimiGo-Lab`、
  `/Users/mr.simi/Documents/SimiGo-Lab-R01-Fixtures` 已不存在；本目录是它们的完整副本。
- `SimiGo-Lab-repo/.git` 的 `origin` 仍指向原远程地址；若远程被删除，本地全部分支、标签与历史仍可从这里恢复。
- 本目录不参与构建，也没有校验清单；Git 跟踪部分的校验见各自目录的 `MANIFEST_SHA256.txt`。
