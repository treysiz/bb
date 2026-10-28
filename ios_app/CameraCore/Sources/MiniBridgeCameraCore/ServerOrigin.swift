import Foundation

enum ServerAddressError: LocalizedError {
    case invalid
    var errorDescription: String? { "请输入不带用户名、密码、路径或参数的 HTTPS 服务器地址。" }
}

struct ServerOrigin: Equatable {
    static let defaultAddress = "https://zhangjunqiao.duckdns.org:18443"
    let url: URL
    let host: String
    let port: Int
    var address: String { String(url.absoluteString.dropLast()) }

    init(_ input: String) throws {
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.port == nil || (1...65535).contains(parts.port!) else { throw ServerAddressError.invalid }
        self.host = host.lowercased()
        self.port = parts.port ?? 443
        parts.scheme = "https"
        parts.host = self.host
        parts.port = port == 443 ? nil : port
        parts.path = "/"
        guard let url = parts.url else { throw ServerAddressError.invalid }
        self.url = url
    }

    func allows(_ candidate: URL) -> Bool {
        guard let parts = URLComponents(url: candidate, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme?.lowercased() == "https" && parts.host?.lowercased() == host &&
            (parts.port ?? 443) == port && parts.user == nil && parts.password == nil
    }

    func allowsResource(_ candidate: URL) -> Bool {
        if candidate.scheme?.lowercased() == "blob" {
            guard let inner = URL(string: String(candidate.absoluteString.dropFirst(5))) else { return false }
            return allows(inner)
        }
        return allows(candidate)
    }
}

enum CameraDownloadPolicy {
    static let maxBytes: Int64 = 64 * 1024 * 1024
    static func filename(_ suggested: String) -> String {
        let unsafe = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        let name = suggested.components(separatedBy: unsafe).joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return name.isEmpty ? "MiniBridge-download" : String(name.prefix(120))
    }
}
