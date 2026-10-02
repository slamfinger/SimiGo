import CryptoKit
import Foundation
import InformationCore

enum InformationMinter {
    static func makeInformationID(namespace: String, content: String, source: String?) -> InformationID {
        let parts = [namespace, content, source ?? "", "0"]
        let key = parts.map { "\($0.utf8.count):\($0)" }.joined()
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return InformationID(rawValue: String(hex.prefix(24)))
    }
}
