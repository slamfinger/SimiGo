# R01 Fixtures 导入排除清单

来源：`/Users/mr.simi/Documents/SimiGo-Lab-R01-Fixtures`（快照于 2026-10-26）。
纳入规则：夹具数据、清单、控制/观测/回执 JSON、准备与 recon 的源码；排除 SwiftPM 构建目录。

## 排除项

| 路径 | 文件数 | 体积 | 原因 |
| --- | ---: | ---: | --- |
| `prep/.build/` | 1618 | 90.9 MiB | SwiftPM 构建产物，可再生成 |
| `recon/.build/` | 1596 | 89.9 MiB | SwiftPM 构建产物，可再生成 |
| `**/.DS_Store` | 1 | — | macOS 元数据 |

纳入 `SimiGo-Lab-R01-Fixtures` 下其余文件（76 个，约 2.3 MiB）。
