import Foundation
import LOCALBCore

/// LOCALB 生产激活的运维入口（PR #14 复审判定的头号阻塞闭合）。
///
/// 设计事实：`LOCALBHostBootstrap.activateInitialSetup` 要求「外部记录的
/// checkpoint 与当前注册表头字节相等」——外部记录本身就是信任锚，把激
/// 活自动接进普通启动会让自我证明变得空洞、违背 B 线安全属性。因此闭
/// 合方式不是自动接线，而是本文件：产品自带的 provisioning 启动模式，
/// 把 prepareFirstRun →（人工外部记录）→ activateInitialSetup →
/// persistTrustedCheckpoint 串成可重复执行的受支持流程。
///
/// 用法（在 app 二进制上）：
///   SimiGo.app/Contents/MacOS/SimiGo --localb-prepare
///   SimiGo.app/Contents/MacOS/SimiGo --localb-activate <recorded.json>
///   SimiGo.app/Contents/MacOS/SimiGo --localb-status
///
/// 步骤文档见 docs/LOCALB_PROVISIONING.md；机器形态的可重复验证见
/// SimiGoTests/LOCALBProvisioningWiringTests。
extension Optional {
    fileprivate func unwrapOrThrow() throws -> Wrapped {
        guard let self else {
            throw LOCALBStatus.registryCorrupt
        }
        return self
    }
}

enum LOCALBProvisioning {

    /// prepare 输出 / activate 输入的记录格式：与
    /// trusted-checkpoint.json 同构（lineageID/sequence/headHashHex）。
    struct RecordedCheckpoint: Codable {
        var lineageID: String
        var sequence: UInt64
        var headHashHex: String
    }

    struct ActivationReceipt: Codable {
        let lineageID: String
        let sequence: UInt64
        let signerKeyID: String
        let transportSPKIHashHex: String
    }

    /// 阶段一：显式首跑仪式。创建钥匙串签名密钥、TLS 传输身份与注册表
    /// 谱系第一代，返回 SETUP/PENDING 凭据——操作者必须把输出**记录到
    /// SimiGo 之外**（这就是外部信任锚），再进入 activate。
    static func prepare(
        hostDirectory: URL? = nil,
        keychainStore: LOCALBKeychainSignerStore = LOCALBKeychainSignerStore(),
        transportIdentityStore: LOCALBTransportIdentityStore =
            LOCALBTransportIdentityStore()
    ) throws -> String {
        let directory = hostDirectory
            ?? LOCALBHostRuntime.defaultHostDirectory()
        let pending = try LOCALBHostBootstrap.prepareFirstRun(
            rootURL: LOCALBHostRuntime.registryRoot(in: directory),
            keychainStore: keychainStore,
            transportIdentityStore: transportIdentityStore)
        let recorded = RecordedCheckpoint(
            lineageID: pending.checkpoint.lineageID,
            sequence: pending.checkpoint.sequence,
            headHashHex: pending.checkpoint.headHash.map {
                String(format: "%02x", $0)
            }.joined())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(
            decoding: try encoder.encode(recorded), as: UTF8.self)
    }

    /// 阶段二：操作者回填外部记录的 checkpoint。字节校验通过 → 持久化
    /// trusted-checkpoint.json（此后每次启动 applyDefault 自动走
    /// operational 接线）；任何不一致 fail-closed 且不落盘。
    static func activate(
        recordedJSON: Data,
        hostDirectory: URL? = nil,
        keychainStore: LOCALBKeychainSignerStore = LOCALBKeychainSignerStore(),
        transportIdentityStore: LOCALBTransportIdentityStore =
            LOCALBTransportIdentityStore()
    ) throws -> ActivationReceipt {
        let directory = hostDirectory
            ?? LOCALBHostRuntime.defaultHostDirectory()
        let recorded = try JSONDecoder().decode(
            RecordedCheckpoint.self, from: recordedJSON)
        let headHash = try LOCALBHostRuntime.decodeLowerHex(
            recorded.headHashHex, count: 32)
            .unwrapOrThrow()
        let checkpoint = try LOCALBRegistryCheckpoint(
            lineageID: recorded.lineageID,
            sequence: recorded.sequence,
            headHash: headHash)
        let context = try LOCALBHostBootstrap.activateInitialSetup(
            rootURL: LOCALBHostRuntime.registryRoot(in: directory),
            operatorRecordedCheckpoint: checkpoint,
            keychainStore: keychainStore,
            transportIdentityStore: transportIdentityStore)
        try LOCALBHostRuntime.persistTrustedCheckpoint(
            checkpoint, in: directory)
        let receipt = try context.currentTrustedCheckpoint()
        return ActivationReceipt(
            lineageID: receipt.lineageID,
            sequence: receipt.sequence,
            signerKeyID: context.signerKeyID,
            transportSPKIHashHex: context.transportIdentity.spkiSHA256Hex)
    }

    /// 可重复的状态核查：已激活 → 验证链全绿输出凭据；未激活 → 明确
    /// not-initialized；损坏 → fail-closed 报错。
    static func status(
        hostDirectory: URL? = nil,
        keychainStore: LOCALBKeychainSignerStore = LOCALBKeychainSignerStore(),
        transportIdentityStore: LOCALBTransportIdentityStore =
            LOCALBTransportIdentityStore()
    ) throws -> String {
        let directory = hostDirectory
            ?? LOCALBHostRuntime.defaultHostDirectory()
        switch try LOCALBHostRuntime.resolveOperational(
            hostDirectory: directory,
            keychainStore: keychainStore,
            transportIdentityStore: transportIdentityStore) {
        case .operational(let context):
            let checkpoint = try context.currentTrustedCheckpoint()
            return "activated lineage=\(checkpoint.lineageID)"
                + " sequence=\(checkpoint.sequence)"
                + " signer=\(context.signerKeyID)"
                + " spki=\(context.transportIdentity.spkiSHA256Hex)"
        case .notInitialized:
            return "not-activated"
        }
    }

    /// 启动参数分派。返回 nil = 本次不是 provisioning 调用（正常启动
    /// 继续）；非 nil = 已完成 provisioning 模式，返回进程退出码。
    @discardableResult
    static func runFromArguments(
        _ arguments: [String],
        hostDirectory: URL? = nil,
        keychainStore: LOCALBKeychainSignerStore = LOCALBKeychainSignerStore(),
        transportIdentityStore: LOCALBTransportIdentityStore =
            LOCALBTransportIdentityStore()
    ) -> Int32? {
        guard arguments.contains("--localb-prepare")
            || arguments.contains("--localb-activate")
            || arguments.contains("--localb-status")
        else {
            return nil
        }
        do {
            if arguments.contains("--localb-status") {
                print(try status(
                    hostDirectory: hostDirectory,
                    keychainStore: keychainStore,
                    transportIdentityStore: transportIdentityStore))
                return 0
            }
            if arguments.contains("--localb-prepare") {
                // stdout 只承载 checkpoint JSON：操作者重定向整个 stdout
                // 即得可直接回填 --localb-activate 的记录文件；提示走 stderr。
                print(try prepare(
                    hostDirectory: hostDirectory,
                    keychainStore: keychainStore,
                    transportIdentityStore: transportIdentityStore))
                FileHandle.standardError.write(Data(
                    ("# 已打印待记录 checkpoint JSON。记录到 SimiGo 之外的"
                        + "受信任位置，再以 --localb-activate <file> 完成激活。\n")
                        .utf8))
                return 0
            }
            guard let index = arguments.firstIndex(of: "--localb-activate"),
                  arguments.count > index + 1
            else {
                FileHandle.standardError.write(
                    Data("--localb-activate 需要一个记录文件路径\n".utf8))
                return 2
            }
            let recorded = try Data(
                contentsOf: URL(fileURLWithPath: arguments[index + 1]))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(
                decoding: try encoder.encode(
                    try activate(
                        recordedJSON: recorded,
                        hostDirectory: hostDirectory,
                        keychainStore: keychainStore,
                        transportIdentityStore: transportIdentityStore)),
                as: UTF8.self))
            return 0
        } catch {
            FileHandle.standardError.write(
                Data("localb provisioning failed: \(error)\n".utf8))
            return 1
        }
    }
}
