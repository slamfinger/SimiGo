import LOCALBCore
import XCTest

@testable import SimiGo

/// 生产激活闭环的可重复机器验证（PR #14 复审头号阻塞的闭合证据）：
/// prepare →（外部记录语义=把输出 JSON 原样传递）→ activate →
/// trusted-checkpoint.json 落盘 → applyDefault 的读取路径能解析为
/// operational。全程使用临时 hostDirectory，不触碰真实 ~/.simigo。
final class LOCALBProvisioningWiringTests: XCTestCase {

    /// 一次性隔离的 host 侧三件套：目录 + 钥匙串签名服务 + 传输身份
    /// 服务（默认服务在开发机上会累积 E2E 夹具的身份 → loadExisting
    /// fail-closed，必须隔离）。测试收尾删除一次性钥匙串条目。
    private func makeIsolatedHost() throws -> (
        directory: URL,
        keychain: LOCALBKeychainSignerStore,
        transport: LOCALBTransportIdentityStore
    ) {
        let nonce = UUID().uuidString
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "localb-prov-\(nonce)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
        let keychain = LOCALBKeychainSignerStore(
            service: "localb-prov-test-\(nonce)")
        let transport = LOCALBTransportIdentityStore(
            service: "localb-prov-test-\(nonce)")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "localb-prov-test-\(nonce)"
            ]
            SecItemDelete(query as CFDictionary)
        }
        return (url, keychain, transport)
    }

    func testPrepareActivatePersistsOperationalCheckpoint() throws {
        let host = try makeIsolatedHost()

        // 阶段一：prepare 输出外部记录 JSON。
        let recordedJSON = try LOCALBProvisioning.prepare(
            hostDirectory: host.directory,
            keychainStore: host.keychain,
            transportIdentityStore: host.transport)
        let recorded = try JSONDecoder().decode(
            LOCALBProvisioning.RecordedCheckpoint.self,
            from: Data(recordedJSON.utf8))
        // 注册密钥本身推进序号（genesis=1 → 注册后=2），不硬编码具体值。
        XCTAssertGreaterThanOrEqual(recorded.sequence, 1)
        XCTAssertEqual(recorded.headHashHex.count, 64)

        // 阶段二：以外部记录激活 → 持久化 checkpoint。
        let receipt = try LOCALBProvisioning.activate(
            recordedJSON: Data(recordedJSON.utf8),
            hostDirectory: host.directory,
            keychainStore: host.keychain,
            transportIdentityStore: host.transport)
        XCTAssertEqual(receipt.lineageID, recorded.lineageID)
        XCTAssertFalse(receipt.transportSPKIHashHex.isEmpty)

        // 读取路径：applyDefault 消费的就是这份落盘 checkpoint。
        let persisted = try XCTUnwrap(
            LOCALBHostRuntime.loadPersistedTrustedCheckpoint(
                in: host.directory))
        XCTAssertEqual(persisted.lineageID, recorded.lineageID)
        XCTAssertEqual(persisted.sequence, recorded.sequence)
        if case .operational(let context) = try LOCALBHostRuntime
            .resolveOperational(
                hostDirectory: host.directory,
                keychainStore: host.keychain,
                transportIdentityStore: host.transport) {
            XCTAssertEqual(context.signerKeyID, receipt.signerKeyID)
        } else {
            XCTFail("activated host must resolve operational")
        }

        // status 口径：已激活。
        XCTAssertTrue(
            try LOCALBProvisioning.status(
                hostDirectory: host.directory,
                keychainStore: host.keychain,
                transportIdentityStore: host.transport)
                .hasPrefix("activated lineage="))
    }

    func testActivateRejectsMismatchedRecordedCheckpoint() throws {
        let host = try makeIsolatedHost()

        let recordedJSON = try LOCALBProvisioning.prepare(
            hostDirectory: host.directory,
            keychainStore: host.keychain,
            transportIdentityStore: host.transport)
        var tampered = try JSONDecoder().decode(
            LOCALBProvisioning.RecordedCheckpoint.self,
            from: Data(recordedJSON.utf8))
        tampered.headHashHex = String(
            repeating: "0", count: 64)  // 篡改的外部记录
        let tamperedData = try JSONEncoder().encode(tampered)

        XCTAssertThrowsError(
            try LOCALBProvisioning.activate(
                recordedJSON: tamperedData,
                hostDirectory: host.directory,
                keychainStore: host.keychain,
                transportIdentityStore: host.transport))
        // fail-closed：激活失败不得留下 checkpoint。
        XCTAssertNil(try LOCALBHostRuntime.loadPersistedTrustedCheckpoint(
            in: host.directory))
    }

    func testRunFromArgumentsReturnsNilForNormalLaunch() {
        XCTAssertNil(LOCALBProvisioning.runFromArguments(
            ["SimiGo"], hostDirectory: nil))
        XCTAssertNil(LOCALBProvisioning.runFromArguments(
            ["SimiGo", "--flag"], hostDirectory: nil))
    }
}
