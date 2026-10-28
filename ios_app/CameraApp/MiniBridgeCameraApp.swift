import SwiftUI
import UIKit
import WebKit

@main
@MainActor
struct MiniBridgeCameraApp: App {
    @StateObject private var browser = CameraBrowserModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            CameraHome(browser: browser)
                .onChange(of: phase) { phase in
                    if phase == .background { Task { await browser.pauseViewing() } }
                    if phase == .active { Task { await browser.resumeViewing() } }
                }
        }
    }
}

@MainActor
struct CameraHome: View {
    @ObservedObject var browser: CameraBrowserModel
    @State private var settings = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "video.fill").foregroundStyle(.teal)
                Text("MiniBridge").font(.headline)
                Spacer()
                Button { Task { await browser.reload() } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("刷新并重新连接")
                    .padding(.horizontal, 12)
                Button { settings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("服务器设置")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            if browser.loading { ProgressView().progressViewStyle(.linear).tint(.teal) }
            CameraBrowserView(browser: browser)
            if !browser.status.isEmpty {
                Text(browser.status).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(.thinMaterial)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $settings) { CameraServerSettings(browser: browser) }
        .sheet(item: $browser.sharedFile, onDismiss: { browser.removeSharedFile() }) { item in
            CameraShareView(url: item.url)
        }
    }
}

@MainActor
struct CameraServerSettings: View {
    @ObservedObject var browser: CameraBrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var message = ""
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    TextField("HTTPS 地址", text: $address)
                        .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                    Text("使用与浏览器相同的 NAS 地址和会员账号。更换服务器会停止本页播放。")
                        .font(.caption).foregroundStyle(.secondary)
                    if !message.isEmpty { Text(message).foregroundStyle(.red) }
                    Button(saving ? "正在连接…" : "保存并连接") {
                        saving = true
                        Task {
                            do { try await browser.connect(to: address); dismiss() }
                            catch { message = error.localizedDescription }
                            saving = false
                        }
                    }.disabled(saving)
                }
                Section("摄像与声音内测") {
                    Text("登录后选择设备，打开实时摄像并点击开始。伴音由超级管理员授权。")
                    Text("支持横屏观看；锁屏或切换到其他 App 会暂停本页播放，返回后手动开始。NAS 自动监测继续运行。")
                    Text("声音来自 ESP 的麦克风，不会使用 iPhone 的摄像头或麦克风。")
                }
                Section("版本") { Text("MiniBridge 摄像内测版 0.2.0") }
            }
            .navigationTitle("App 设置")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(saving) } }
            .onAppear { address = browser.origin.address }
        }
    }
}

@MainActor
struct CameraBrowserView: UIViewControllerRepresentable {
    @ObservedObject var browser: CameraBrowserModel
    func makeUIViewController(context: Context) -> CameraBrowserController {
        let controller = CameraBrowserController()
        browser.presenter = controller
        controller.attach(browser.webView)
        return controller
    }
    func updateUIViewController(_ controller: CameraBrowserController, context: Context) { controller.attach(browser.webView) }
}

final class CameraBrowserController: UIViewController {
    private weak var browserView: WKWebView?
    func attach(_ webView: WKWebView?) {
        guard let webView, browserView !== webView else { return }
        loadViewIfNeeded()
        browserView?.removeFromSuperview()
        browserView = webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

@MainActor
struct CameraShareView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
