# Historical release records

本目录保存旧版本 release notes 与阶段冻结记录。它们只说明各自版本 / commit 的历史内容，不是当前下载入口、支持版本表或当前 main 的功能清单。

## Release notes

- [v1.3](RELEASE_NOTES_v1.3.md)
- [v1.5](RELEASE_NOTES_v1.5.md)
- [v1.6](RELEASE_NOTES_v1.6.md)
- [v1.7](RELEASE_NOTES_v1.7.md)
- [v2.1.0](RELEASE_NOTES_v2.1.0.md)
- [v2.1.1](RELEASE_NOTES_v2.1.1.md)
- [v2.1.2](RELEASE_NOTES_v2.1.2.md)
- [v2.1.3](RELEASE_NOTES_v2.1.3.md)
- [v2.1.4](RELEASE_NOTES_v2.1.4.md)
- [v2.1.5](RELEASE_NOTES_v2.1.5.md)
- [v2.1.6](RELEASE_NOTES_v2.1.6.md)
- [v2.2.7](RELEASE_NOTES_v2.2.7.md)
- [v2.2.7 (2)](RELEASE_NOTES_v2.2.7-2.md)
- [v2.2.7 (3)](RELEASE_NOTES_v2.2.7-3.md)
- [历史候选：v2.2.4 build 34](HISTORICAL_CANDIDATE_v2.2.4-34.md)（未公开发布的本地候选，仅溯源）

## Technical baselines

- [v1.6 final baseline](V16_FINAL_BASELINE_20260919.md)
- [v2.0 Beta Execution State freeze](BETA_RELEASE_FREEZE_EXECUTION_STATE_20260929.md)

## Artifact manifest

本目录**不保存安装包本体**。[RELEASES_ARTIFACTS_MANIFEST.tsv](RELEASES_ARTIFACTS_MANIFEST.tsv) 记录历史 31 个 DMG 的 tag、文件名、字节数与 SHA-256（取自发布时的上游 asset digest），并标注重复产物。上游 release 与 tag 均已不存在，该 manifest 是这些产物的身份记录；DMG 本体只保存在本仓之外的本地归档中。

## Current distribution status

See the repository-root [README](../../README.md) and [RELEASE.md](../../RELEASE.md). A historical release note does not establish that its artifact is still available, supported, or compatible with current `main`.
