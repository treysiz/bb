import AuthenticationServices
import CommonCrypto
import CryptoKit
import Foundation
import Security

struct VaultRecord: Codable, Identifiable {
    let id: String
    let title: String
    let category: String
    let site: String
    let username: String
    let password: String
    let notes: String
}

final class VaultRepository {
    static let shared = VaultRepository()
    private let rounds: UInt32 = 600_000
    private init() {}

    func pair(origin: String, code: String, masterPassword: String) async throws {
        let normalized = try normalize(origin)
        let reply = try await exchange(origin: normalized, auth: ["type": "pair", "code": code], operation: nil)
        guard let token = reply["token"] as? String, !token.isEmpty else { throw VaultFailure.pairing }
        try VaultKeychain.setToken(token, origin: normalized)
        try await unlock(masterPassword: masterPassword)
    }

    func unlock(masterPassword: String) async throws {
        guard masterPassword.count >= 12 else { throw VaultFailure.shortMasterPassword }
        let list = try await request(["type": "list"])
        guard let saltText = list["salt"] as? String, let entries = list["entries"] as? [String: [String: String]] else {
            throw VaultFailure.badResponse
        }
        let key = try Self.derive(masterPassword: masterPassword, salt: Self.decode(saltText), rounds: rounds)
        if let verifier = entries["vault-verifier"] {
            let value = try Self.open(verifier, id: "vault-verifier", key: key)
            guard value["value"] as? String == "MiniBridgeVaultV1" else { throw VaultFailure.wrongMasterPassword }
        } else {
            let sealed = try Self.seal(["value": "MiniBridgeVaultV1"], id: "vault-verifier", key: key)
            _ = try await request(["type": "put", "id": "vault-verifier", "iv": sealed.iv, "ciphertext": sealed.ciphertext])
        }
        try VaultKeychain.setVaultKey(key)
    }

    func records(for identifier: String? = nil) async throws -> [VaultRecord] {
        let key = try VaultKeychain.vaultKey()
        let list = try await request(["type": "list"])
        guard let entries = list["entries"] as? [String: [String: String]] else { throw VaultFailure.badResponse }
        var result: [VaultRecord] = []
        for (id, sealed) in entries where id != "vault-verifier" {
            guard var object = try? Self.open(sealed, id: id, key: key) else { continue }
            object["id"] = id
            guard let data = try? JSONSerialization.data(withJSONObject: object),
                  let record = try? JSONDecoder().decode(VaultRecord.self, from: data) else { continue }
            if let identifier {
                if Self.matches(record.site, identifier: identifier) { result.append(record) }
            } else { result.append(record) }
        }
        return result
    }

    func save(site: String, username: String, password: String, title: String? = nil, isApp: Bool = false) async throws {
        let key = try VaultKeychain.vaultKey()
        let id = "ios_" + Self.encode(SecureRandom.bytes(count: 18))
        let cleanSite = Self.normalizedService(site, isApp: isApp)
        let record = VaultRecord(id: id, title: title?.isEmpty == false ? title! : cleanSite,
                                 category: "网站登录", site: cleanSite, username: username,
                                 password: password, notes: "")
        let object: [String: Any] = ["title": record.title, "category": record.category, "site": record.site,
                                     "username": record.username, "password": record.password, "notes": record.notes]
        let sealed = try Self.seal(object, id: id, key: key)
        let reply = try await request(["type": "put", "id": id, "iv": sealed.iv, "ciphertext": sealed.ciphertext])
        guard reply["type"] as? String == "saved" else { throw VaultFailure.saveFailed }
    }

    func identities() async throws -> [ASPasswordCredentialIdentity] {
        let saved = try await records()
        return saved.compactMap { record in
            let isApp = record.site.hasPrefix("app://")
            let identifier = isApp ? String(record.site.dropFirst(6)) : (URLComponents(string: record.site)?.host ?? "")
            guard !identifier.isEmpty, !record.password.isEmpty else { return nil }
            let service = ASCredentialServiceIdentifier(identifier: identifier, type: isApp ? .app : .domain)
            return ASPasswordCredentialIdentity(serviceIdentifier: service, user: record.username, recordIdentifier: record.id)
        }
    }

    private func request(_ operation: [String: Any]) async throws -> [String: Any] {
        let connection = try VaultKeychain.connection()
        return try await exchange(origin: connection.origin,
                                  auth: ["type": "auth", "token": connection.token], operation: operation)
    }

    private func exchange(origin: String, auth: [String: Any], operation: [String: Any]?) async throws -> [String: Any] {
        guard let base = URL(string: origin), base.scheme == "https", let host = base.host else { throw VaultFailure.badOrigin }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.scheme = "wss"; components.path = "/vault"
        guard let url = components.url else { throw VaultFailure.badOrigin }
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }
        try await task.send(.string(Self.json(auth)))
        while true {
            let message = try Self.object(await task.receive())
            switch message["type"] as? String {
            case "authenticated":
                if message["token"] as? String != nil { return message }
                if let operation { try await task.send(.string(Self.json(operation))) }
                else { return message }
            case "entries", "saved": return message
            case "error": throw VaultFailure.serverRejected(message["code"] as? String ?? "请求失败")
            default: continue
            }
        }
    }

    private static func derive(masterPassword: String, salt: Data, rounds: UInt32) throws -> Data {
        var output = [UInt8](repeating: 0, count: 32)
        let passwordBytes = Array(masterPassword.utf8)
        let status = passwordBytes.withUnsafeBytes { password in
            salt.withUnsafeBytes { saltBytes in
                output.withUnsafeMutableBytes { outputBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                        password.baseAddress?.assumingMemoryBound(to: Int8.self), password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                        outputBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), outputBytes.count)
                }
            }
        }
        guard status == kCCSuccess else { throw VaultFailure.crypto }
        return Data(output)
    }

    private static func seal(_ object: [String: Any], id: String, key: Data) throws -> (iv: String, ciphertext: String) {
        let nonce = AES.GCM.Nonce(data: SecureRandom.bytes(count: 12))
        let plain = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let sealed = try AES.GCM.seal(plain, using: SymmetricKey(data: key), nonce: nonce,
                                      authenticating: Data(id.utf8))
        let iv = Data(nonce)
        return (encode(iv), encode(sealed.ciphertext + sealed.tag))
    }

    private static func open(_ item: [String: String], id: String, key: Data) throws -> [String: Any] {
        guard let ivText = item["iv"], let cipherText = item["ciphertext"] else { throw VaultFailure.badResponse }
        let nonce = try AES.GCM.Nonce(data: decode(ivText)), combined = decode(cipherText)
        guard combined.count >= 16 else { throw VaultFailure.badResponse }
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: combined.dropLast(16), tag: combined.suffix(16))
        let plain = try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Data(id.utf8))
        return try JSONSerialization.jsonObject(with: plain) as? [String: Any] ?? [:]
    }

    private static func object(_ message: URLSessionWebSocketTask.Message) throws -> [String: Any] {
        switch message {
        case .string(let text): return try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] ?? [:]
        case .data(let data): return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        @unknown default: throw VaultFailure.badResponse
        }
    }
    private static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
    private static func encode(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    private static func decode(_ text: String) -> Data {
        let standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: standard + String(repeating: "=", count: (4 - standard.count % 4) % 4)) ?? Data()
    }
    private static func normalize(_ origin: String) throws -> String {
        guard let parts = URLComponents(string: origin.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let host = parts.host, !host.isEmpty, parts.path.isEmpty || parts.path == "/" else { throw VaultFailure.badOrigin }
        return "https://" + host + (parts.port.map { ":\($0)" } ?? "")
    }
    private static func normalizedService(_ input: String, isApp: Bool = false) -> String {
        if isApp { return input.hasPrefix("app://") ? input : "app://" + input }
        if input.hasPrefix("app://") { return input }
        if input.hasPrefix("https://") { return input }
        return "https://" + input
    }
    private static func matches(_ site: String, identifier: String) -> Bool {
        if site.hasPrefix("app://") { return site.dropFirst(6).caseInsensitiveCompare(identifier) == .orderedSame }
        return URLComponents(string: site)?.host?.caseInsensitiveCompare(identifier) == .orderedSame
    }
}

private enum SecureRandom {
    static func bytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}

enum VaultFailure: LocalizedError {
    case pairing, shortMasterPassword, wrongMasterPassword, badResponse, badOrigin, crypto, saveFailed
    case serverRejected(String)
    var errorDescription: String? {
        switch self {
        case .pairing: return "配对码无效、过期或已使用。"
        case .shortMasterPassword: return "密码库主密码至少需要 12 个字符。"
        case .wrongMasterPassword: return "密码库主密码错误。"
        case .badResponse: return "密码库服务器响应无效。"
        case .badOrigin: return "请输入可信 HTTPS 服务器地址。"
        case .crypto: return "无法完成密码库加密操作。"
        case .saveFailed: return "服务器未确认保存。"
        case .serverRejected(let reason): return "服务器拒绝请求：\(reason)"
        }
    }
}
