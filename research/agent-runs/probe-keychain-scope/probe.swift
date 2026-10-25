import Foundation
import Security

let path = "/Users/mr.simi/SimiGo-Agent-Runs/probe-keychain-scope/probe.keychain-db"
func p(_ s: String, _ st: OSStatus) { print("\(s): \(st) \(SecCopyErrorMessageString(st, nil).map{String(describing:$0)} ?? "")") }

var kc: SecKeychain?
p("open", SecKeychainOpen(path, &kc))
guard let kc else { fatalError("no kc") }
p("unlock", SecKeychainUnlock(kc, UInt32("probe".utf8.count), "probe", true))

// 1. generic password scoped add
let svc = "probe.service.v1"
SecItemDelete([kSecClass as String: kSecClassGenericPassword,
               kSecAttrService as String: svc,
               kSecMatchSearchList as String: [kc]] as CFDictionary)
let add: [String: Any] = [
  kSecClass as String: kSecClassGenericPassword,
  kSecAttrService as String: svc,
  kSecAttrAccount as String: "acc",
  kSecValueData as String: Data("x".utf8),
  kSecUseKeychain as String: kc
]
p("gp add scoped", SecItemAdd(add as CFDictionary, nil))
var r: CFTypeRef?
let scoped = SecItemCopyMatching([kSecClass as String: kSecClassGenericPassword,
  kSecAttrService as String: svc, kSecReturnData as String: true,
  kSecMatchSearchList as String: [kc]] as CFDictionary, &r)
p("gp copy scoped (expect 0)", scoped)
let unscoped = SecItemCopyMatching([kSecClass as String: kSecClassGenericPassword,
  kSecAttrService as String: svc, kSecReturnData as String: true] as CFDictionary, &r)
p("gp copy unscoped (expect itemNotFound)", unscoped)

// 2. key generation scoped
let tag = Data("probe-tag-\(UUID().uuidString)".utf8)
let keyAttrs: [String: Any] = [
  kSecClass as String: kSecClassKey,
  kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
  kSecAttrKeySizeInBits as String: 256,
  kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
  kSecAttrApplicationTag as String: tag,
  kSecAttrIsPermanent as String: true,
  kSecUseKeychain as String: kc
]
let gen = SecKeyCreateRandomKey(keyAttrs as CFDictionary, nil)
print("seckey create scoped: \(gen != nil)")
p("key copy scoped (expect 0)", SecItemCopyMatching([kSecClass as String: kSecClassKey,
  kSecAttrApplicationTag as String: tag, kSecReturnRef as String: true,
  kSecMatchSearchList as String: [kc]] as CFDictionary, &r))
p("key copy unscoped (expect 0 if leaked to login)", SecItemCopyMatching([kSecClass as String: kSecClassKey,
  kSecAttrApplicationTag as String: tag, kSecReturnRef as String: true] as CFDictionary, &r))

// 3. identity synthesis inside the scoped keychain (imported cert+key)
var certs: CFTypeRef?
p("cert copy scoped", SecItemCopyMatching([kSecClass as String: kSecClassCertificate,
  kSecReturnRef as String: true, kSecMatchSearchList as String: [kc]] as CFDictionary, &certs))
var firstCert: SecCertificate? = nil
if let arr = certs as? [SecCertificate] { firstCert = arr.first }
else if let single = certs { firstCert = (single as! SecCertificate) }
if let c = firstCert {
  var ident: SecIdentity?
  p("identity create scoped (expect 0)", SecIdentityCreateWithCertificate(kc, c, &ident))
  print("identity scoped non-nil: \(ident != nil)")
  var ident2: SecIdentity?
  p("identity create nil-kc (expect itemNotFound)", SecIdentityCreateWithCertificate(nil, c, &ident2))
}
