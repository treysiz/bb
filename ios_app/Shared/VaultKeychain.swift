import Foundation
import LocalAuthentication
import Security

enum VaultKeychain {
    struct Connection { let origin: String; let token: String }
    private static let service = "com.minibridge.passwords"
    private static var accessGroup: String? { Bundle.main.object(forInfoDictionaryKey: "MBSharedKeychainGroup") as? String }

    static func setToken(_ token: String, origin: String) throws {
        try put(Data(token.utf8), account: "token", access: nil)
        try put(Data(origin.utf8), account: "origin", access: nil)
    }
    static func connection() throws -> Connection {
        guard let token = String(data: try get(account: "token", prompt: nil), encoding: .utf8),
              let origin = String(data: try get(account: "origin", prompt: nil), encoding: .utf8) else { throw VaultFailure.pairing }
        return Connection(origin: origin, token: token)
    }
    static func setVaultKey(_ key: Data) throws {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        try put(key, account: "vault-key", access: access)
    }
    static func vaultKey() throws -> Data { try get(account: "vault-key", prompt: "使用 Face ID 或设备密码解锁 MiniBridge 密码库") }
    static func removeAll() { ["token", "origin", "vault-key"].forEach { SecItemDelete(query(account: $0) as CFDictionary) } }

    private static func put(_ value: Data, account: String, access: SecAccessControl?) throws {
        let base = query(account: account); SecItemDelete(base as CFDictionary)
        var item = base; item[kSecValueData as String] = value
        if let access { item[kSecAttrAccessControl as String] = access }
        else { item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly }
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    private static func get(account: String, prompt: String?) throws -> Data {
        var item = query(account: account); item[kSecReturnData as String] = true; item[kSecMatchLimit as String] = kSecMatchLimitOne
        if let prompt {
            let context = LAContext(); context.localizedReason = prompt
            item[kSecUseAuthenticationContext as String] = context; item[kSecUseOperationPrompt as String] = prompt
        }
        var result: CFTypeRef?; let status = SecItemCopyMatching(item as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound { throw VaultFailure.pairing }
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return data
    }
    private static func query(account: String) -> [String: Any] {
        var item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        if let accessGroup { item[kSecAttrAccessGroup as String] = accessGroup }
        return item
    }
}
