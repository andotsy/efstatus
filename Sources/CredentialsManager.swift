import Foundation
import Security

struct Credentials: Codable {
    let accessKey: String
    let secretKey: String
    let serial: String
}

/// Stores API credentials in the login Keychain. Older versions kept them in
/// UserDefaults (a plain-text plist); load() migrates and deletes those once.
enum CredentialsManager {
    private static let service = "com.efstatus.app"
    private static let account = "ecoflow-api"
    private static let legacyKeys = ["accessKey", "secretKey", "serial"]

    static func save(_ c: Credentials) {
        guard let data = try? JSONEncoder().encode(c) else { return }
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "EFStatus — EcoFlow API credentials"
            SecItemAdd(add as CFDictionary, nil)
        }
        legacyKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    static func load() -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
           let data = out as? Data,
           let c = try? JSONDecoder().decode(Credentials.self, from: data) {
            return c
        }
        return migrateLegacy()
    }

    private static func migrateLegacy() -> Credentials? {
        let d = UserDefaults.standard
        guard
            let ak = d.string(forKey: "accessKey"), !ak.isEmpty,
            let sk = d.string(forKey: "secretKey"), !sk.isEmpty,
            let sn = d.string(forKey: "serial"),    !sn.isEmpty
        else { return nil }
        let c = Credentials(accessKey: ak, secretKey: sk, serial: sn)
        save(c)
        return c
    }
}
