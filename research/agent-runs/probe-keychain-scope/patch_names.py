import sys
p = "/Users/mr.simi/Documents/SimiGo/Packages/LOCALBCore/Sources/LOCALBCore/LOCALBTransportIdentityStore.swift"
s = open(p, encoding="utf-8").read()
pairs = [
 ('    /// Add-side scoping (`kSecUseKeychain`).\n    private func scoped(_ attributes: [String: Any]) throws -> [String: Any] {',
  '    /// Add-side scoping (`kSecUseKeychain`). Public so callers that must issue\n    /// their own Keychain writes (tests, diagnostics) hit the same store.\n    public func scopedAdd(_ attributes: [String: Any]) throws -> [String: Any] {'),
 ('    /// Query-side scoping (`kSecMatchSearchList`) for copy/update/delete.\n    private func searchScoped(_ query: [String: Any]) throws -> [String: Any] {',
  '    /// Query-side scoping (`kSecMatchSearchList`) for copy/update/delete.\n    /// Public for the same reason as `scopedAdd`; it throws instead of silently\n    /// falling back to the login Keychain when a scoped file cannot be opened.\n    public func scopedQuery(_ query: [String: Any]) throws -> [String: Any] {'),
 ('        guard let scopedQuery = try? searchScoped(query) else { return }\n        SecItemDelete(scopedQuery as CFDictionary)',
  '        guard let resolved = try? scopedQuery(query) else { return }\n        SecItemDelete(resolved as CFDictionary)'),
 ('try searchScoped(updateQuery)', 'try scopedQuery(updateQuery)'),
 ('try searchScoped(query)', 'try scopedQuery(query)'),
 ('try searchScoped(keyQuery)', 'try scopedQuery(keyQuery)'),
 ('try scoped(indexAttributes)', 'try scopedAdd(indexAttributes)'),
 ('try scoped(certAttributes)', 'try scopedAdd(certAttributes)'),
]
for i,(o,n) in enumerate(pairs):
    c = s.count(o)
    if c != 1:
        print("FAIL %d count=%d" % (i,c)); sys.exit(1)
    s = s.replace(o,n)
open(p,'w',encoding='utf-8').write(s)
print("renamed ok")
