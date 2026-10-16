import LOCALBCore
import XCTest

/// 钥匙串卫生哨兵（用户纪律 2026-10-16：测试永不使用真实钥匙串）。
///
/// 规则：SimiGoTests 的任何测试都只允许写 `com.simigo.tests.*` 服务名
/// 的一次性隔离条目（UUID 后缀 + deleteAll teardown），默认生产服务名
/// （`com.simigo.localb-production-signer` /
/// `com.simigo.localb-transport-identity`）在测试进程内零新增。
///
/// 本哨兵在进程启动时快照默认服务名的条目计数，进程收尾时断言无增——
/// 任何测试直接使用默认 store 都会让计数上涨并在此红灯，把「开发机
/// 钥匙串被测试污染」这类事故（2026-10-16 实发：默认传输身份库索引与
/// key/cert 代次失配，真机 prepare fail-closed）挡在 CI 与本机。
final class KeychainHygieneSentinelTests: XCTestCase {

    nonisolated(unsafe) static var baselineGeneric = 0
    nonisolated(unsafe) static var baselineCerts = 0
    nonisolated(unsafe) static var counted = false

    private static let productionGenericServices = [
        "com.simigo.localb-production-signer",
        "com.simigo.localb-transport-identity",
    ]

    private static func countGenericPassword(service: String) -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let items = result as? [[String: Any]]
        else {
            return 0  // errSecItemNotFound 等同于零条
        }
        return items.count
    }

    private static func countProductionCerts() -> Int {
        // 传输身份的证书标签形如 "<service>#<account>#cert#g<g>#a<id>"。
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) ==
            errSecSuccess,
              let items = result as? [[String: Any]]
        else {
            return 0
        }
        return items.filter { item in
            guard let label = item[kSecAttrLabel as String] as? String
            else { return false }
            return productionGenericServices.contains {
                label.hasPrefix($0)
            }
        }.count
    }

    /// 进程内第一个执行的测试：取基线。
    func test00BaselineSnapshot() {
        if !Self.counted {
            Self.baselineGeneric = Self.productionGenericServices.reduce(0) {
                $0 + Self.countGenericPassword(service: $1)
            }
            Self.baselineCerts = Self.countProductionCerts()
            Self.counted = true
        }
    }

    /// 进程内最后执行的测试（名字序）：默认服务名零新增即通过。
    /// 与 test00BaselineSnapshot 之间隔开足够命名距离，吞掉其他全部
    /// 测试对默认库的任何直接写入。
    func testZZDefaultKeychainUntouchedByTests() {
        test00BaselineSnapshot()  // 独跑本测试时也要有基线
        let nowGeneric = Self.productionGenericServices.reduce(0) {
            $0 + Self.countGenericPassword(service: $1)
        }
        let nowCerts = Self.countProductionCerts()
        XCTAssertEqual(
            nowGeneric, Self.baselineGeneric,
            "测试进程向生产钥匙串服务写入了新的 generic-password 条目——" +
                "违规测试必须改用 com.simigo.tests.* 隔离服务名")
        XCTAssertEqual(
            nowCerts, Self.baselineCerts,
            "测试进程写入了生产传输身份证书——违规测试必须改用 " +
                "com.simigo.tests.* 隔离服务名")
    }
}
