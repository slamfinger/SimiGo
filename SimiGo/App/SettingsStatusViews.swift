import SwiftUI
import SimiGoRuntimeContract

/// Read-only status lines extracted verbatim from Settings (D7 pilot): the
/// version footer block, the gap counter line and the ownership-retry line.

struct SettingsVersionSection: View {
    var body: some View {

    VStack(alignment: .leading, spacing: 10) {
        Text(Settings.versionFooter)
            .font(.title3.monospaced())
            .textSelection(.enabled)
        Text("本地推理 + 信息空间。库只存，判断在模型这边。")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        Link(destination: Settings.repoURL) {
            Label("github.com/slamfinger/SimiGo", systemImage: "link")
                .font(.caption)
        }
        HStack(spacing: 12) {
            Link("变更记录", destination: Settings.repoURL.appendingPathComponent("tree/main/docs/releases"))
            Link("许可", destination: Settings.repoURL.appendingPathComponent("blob/main/LICENSE"))
            Link("第三方声明", destination: Settings.repoURL.appendingPathComponent("blob/main/THIRD_PARTY_NOTICES.md"))
            Link("安全报告", destination: Settings.repoURL.appendingPathComponent("blob/main/SECURITY.md"))
        }
        .font(.caption2)

        Divider()

        Text("升级影响：数据库只做前向迁移（当前 schema 36，旧库就地升级、不回退）；"
            + "覆盖安装会清掉首次运行标记，重走一遍首启向导。")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Text("build 号是候选版序号，不是发版信号；装上不等于发布。")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsGapLine: View {
    let gaps: ESISDatabase.TurnGapCounts?
    let busy: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {

    VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 10) {
            if let gaps {
                Text("缺口：轮账 \(gaps.ledgerSessions) 个会话 · 时间 \(gaps.times) 轮 · "
                    + "摘要 \(gaps.digests) 轮 · 关键词 \(gaps.keywords) 轮 · "
                    + "房间 \(gaps.rooms) 轮")
                    .font(.caption2)
                    .foregroundStyle(gaps.total == 0 ? .secondary : .primary)
            } else {
                Text("正在数缺口…").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if busy {
                Button("停止") { onStop() }
                    .help("停止补录：当前数据库步骤完成后停止；模型生成期间会取消当前请求")
            } else if (gaps?.total ?? 0) > 0 {
                Button("开始") { onStart() }
            }
        }
        // 时间那几格如果只剩导入批次，点「开始」也补不出来：它们的时刻在源
        // 导出里，不在库里的任何一列。说出来，比让人反复点一次要好。
        if let gaps, gaps.times > 0, SourceTimeExport.directory == nil {
            Text("其中 \(gaps.times) 轮时间要 AI Studio／深寻的导出目录：先「信息采集…」选一次。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
    }
}

struct SettingsSpaceRetryLine: View {
    let spaceRetry: ESISDatabase.SpaceAssignmentRetryStatus?
    let gaps: ESISDatabase.TurnGapCounts?

    @ViewBuilder var body: some View {

    let pending = spaceRetry?.pending ?? 0
    let rooms = gaps?.rooms ?? 0
    let abandoned = spaceRetry?.abandoned ?? 0
    if pending > 0 || rooms > 0 {
        HStack(spacing: 8) {
            Text("归属缺口：\(rooms) 轮 · 重试队列 \(pending) 轮"
                + (abandoned > 0 ? " · 已放弃 \(abandoned) 轮" : ""))
                .font(.caption2)
                .foregroundStyle(abandoned > 0 || rooms > 0 ? .primary : .secondary)
            if let last = spaceRetry?.lastError, !last.isEmpty {
                Text(last)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }
    }
}
