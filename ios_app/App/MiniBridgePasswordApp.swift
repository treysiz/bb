import AuthenticationServices
import SwiftUI

@main
struct MiniBridgePasswordApp: App {
    var body: some Scene {
        WindowGroup { PairingView() }
    }
}

struct PairingView: View {
    @State private var origin = UserDefaults.standard.string(forKey: "vaultOrigin") ?? ""
    @State private var pairingCode = ""
    @State private var masterPassword = ""
    @State private var message = "请连接到可信 HTTPS/WSS 密码库。"
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("连接密码库") {
                    TextField("服务器 HTTPS 地址", text: $origin)
                        .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                    TextField("一次性配对码", text: $pairingCode)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("密码库主密码", text: $masterPassword)
                    Button(busy ? "正在连接…" : "配对并解锁") { pair() }.disabled(busy)
                    Button("解锁已配对的密码库") { unlock() }.disabled(busy)
                }
                Section("启用系统自动填充") {
                    Text("配对后，到 iPhone 设置 → 通用 → 自动填充与密码，选择 MiniBridge Password。保存和忽略操作由 iOS 系统界面确认。")
                    Button("刷新系统凭据列表") { refreshIdentities() }
                }
                Section("状态") { Text(message).textSelection(.enabled) }
                Section {
                    Button("本机退出配对", role: .destructive) { VaultKeychain.removeAll(); message = "已从本机清除配对和解锁密钥。服务器中的密文仍保留。" }
                }
            }
            .navigationTitle("MiniBridge 密码库")
        }
    }

    private func pair() {
        run("配对完成，正在校验主密码…") {
            try await VaultRepository.shared.pair(origin: origin, code: pairingCode, masterPassword: masterPassword)
            UserDefaults.standard.set(origin.trimmingCharacters(in: CharacterSet(charactersIn: "/")), forKey: "vaultOrigin")
            await updateIdentities()
            return "已配对并解锁。现在可在 iOS 设置中启用密码自动填充。"
        }
    }

    private func unlock() {
        run("正在验证主密码…") {
            try await VaultRepository.shared.unlock(masterPassword: masterPassword)
            await updateIdentities()
            return "已解锁。iOS 会在读取密码前要求 Face ID 或设备密码。"
        }
    }

    private func refreshIdentities() {
        run("正在刷新系统凭据…") { await updateIdentities(); return "系统凭据列表已刷新。" }
    }

    private func run(_ initial: String, action: @escaping () async throws -> String) {
        busy = true; message = initial
        Task {
            do { message = try await action(); pairingCode = ""; masterPassword = "" }
            catch { message = error.localizedDescription }
            busy = false
        }
    }

    private func updateIdentities() async {
        guard let identities = try? await VaultRepository.shared.identities() else { return }
        try? await ASCredentialIdentityStore.shared.replaceCredentialIdentities(identities)
    }
}
