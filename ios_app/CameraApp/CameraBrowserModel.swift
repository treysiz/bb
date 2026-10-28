import Combine
import Foundation
import UIKit
import WebKit

struct SharedCameraFile: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
final class CameraBrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    @Published private(set) var webView: WKWebView?
    @Published private(set) var loading = false
    @Published private(set) var status = ""
    @Published var sharedFile: SharedCameraFile?
    private(set) var origin: ServerOrigin
    weak var presenter: UIViewController?
    private var dialogCancellation: (() -> Void)?
    private var pendingDownload: WKDownload?
    private var downloadFolder: URL?
    private var downloadFile: URL?
    private var sharedFolder: URL?

    override init() {
        origin = (try? ServerOrigin(UserDefaults.standard.string(forKey: "cameraServerOrigin") ?? "")) ??
            (try! ServerOrigin(ServerOrigin.defaultAddress))
        super.init()
        configureWebView()
    }

    private func configureWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        if let file = Bundle.main.url(forResource: "BridgeLifecycle", withExtension: "js"),
           let script = try? String(contentsOf: file, encoding: .utf8),
           let encoded = try? JSONEncoder().encode(origin.address),
           let address = String(data: encoded, encoding: .utf8) {
            let scoped = "if (window.location.origin === \(address)) {\n\(script)\n}"
            configuration.userContentController.addUserScript(WKUserScript(
                source: scoped, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = false
        view.scrollView.contentInsetAdjustmentBehavior = .automatic
        view.isOpaque = false
        view.backgroundColor = .systemBackground
        webView = view
        loading = true
        status = "正在连接服务器…"
        view.load(URLRequest(url: origin.url, timeoutInterval: 30))
    }

    func pauseViewing() async {
        cancelDialog()
        guard let view = webView, let url = view.url, origin.allows(url) else { return }
        let result = try? await view.evaluateJavaScript("window.MiniBridgeAppLifecycle?.pause()")
        if let values = result as? [String: Bool], values.values.contains(true) {
            status = "本页播放已暂停，返回页面后请点击开始。后台自动监测继续。"
        }
    }

    func reload() async {
        await pauseViewing()
        status = "正在重新连接…"
        if let view = webView, view.url != nil { view.reload() }
        else { webView?.load(URLRequest(url: origin.url, timeoutInterval: 30)) }
    }

    func resumeViewing() async {
        guard let view = webView, let url = view.url, origin.allows(url) else { return }
        _ = try? await view.evaluateJavaScript("window.MiniBridgeAppLifecycle?.resume()")
    }

    func connect(to input: String) async throws {
        let candidate = try ServerOrigin(input)
        guard candidate != origin else { return }
        await pauseViewing()
        clearPendingDownload()
        removeSharedFile()
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        origin = candidate
        UserDefaults.standard.set(candidate.address, forKey: "cameraServerOrigin")
        configureWebView()
    }

    private func navigationError(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        loading = false
        status = "连接失败，请检查网络、服务器地址和 HTTPS 证书，然后点击刷新。"
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        status = "请登录后选择设备，点击开始观看。"
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationError(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationError(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loading = false
        status = "页面已停止，请点击刷新后重新开始观看。必要时请重新登录。"
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if origin.allowsResource(url) {
            decisionHandler(action.shouldPerformDownload ? .download : .allow)
        } else if url.absoluteString == "about:blank" && action.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated && url.scheme == "https" && url.user == nil && url.password == nil {
                UIApplication.shared.open(url)
            } else {
                status = "已阻止离开当前服务器。更换服务器请使用 App 设置。"
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard let url = response.response.url, origin.allowsResource(url) else { decisionHandler(.cancel); return }
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil, let url = action.request.url, origin.allows(url) { webView.load(action.request) }
        return nil
    }

    // This is a remote ESP camera viewer; it never needs the iPhone camera/microphone.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }

    private func canPresentDialog(_ frame: WKFrameInfo) -> Bool {
        guard frame.isMainFrame, let url = frame.request.url, origin.allows(url),
              let presenter, presenter.presentedViewController == nil, dialogCancellation == nil else { return false }
        return true
    }
    private func cancelDialog() {
        let cancellation = dialogCancellation
        dialogCancellation = nil
        cancellation?()
        if cancellation != nil { presenter?.presentedViewController?.dismiss(animated: false) }
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard canPresentDialog(frame) else { completionHandler(); return }
        let alert = UIAlertController(title: "MiniBridge", message: String(message.prefix(2000)), preferredStyle: .alert)
        dialogCancellation = completionHandler
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self] _ in
            self?.dialogCancellation = nil; completionHandler()
        })
        presenter?.present(alert, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard canPresentDialog(frame) else { completionHandler(false); return }
        let alert = UIAlertController(title: "请确认", message: String(message.prefix(2000)), preferredStyle: .alert)
        dialogCancellation = { completionHandler(false) }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.dialogCancellation = nil; completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: "继续", style: .default) { [weak self] _ in
            self?.dialogCancellation = nil; completionHandler(true)
        })
        presenter?.present(alert, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        guard canPresentDialog(frame) else { completionHandler(nil); return }
        let alert = UIAlertController(title: "MiniBridge", message: String(prompt.prefix(2000)), preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        dialogCancellation = { completionHandler(nil) }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.dialogCancellation = nil; completionHandler(nil)
        })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak self, weak alert] _ in
            self?.dialogCancellation = nil; completionHandler(alert?.textFields?.first?.text)
        })
        presenter?.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { begin(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { begin(download) }

    private func begin(_ download: WKDownload) {
        guard pendingDownload == nil, sharedFile == nil else { download.cancel { _ in }; status = "请先完成当前文件的保存。"; return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MiniBridge-" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                attributes: [.protectionKey: FileProtectionType.complete])
            pendingDownload = download
            downloadFolder = folder
            download.delegate = self
            status = "正在下载文件…"
        } catch { download.cancel { _ in }; status = "无法建立临时下载文件。" }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        guard pendingDownload === download, let folder = downloadFolder, let url = response.url,
              origin.allowsResource(url), response.expectedContentLength <= CameraDownloadPolicy.maxBytes else {
            completionHandler(nil); clearPendingDownload(); status = "文件无法下载，或超过 64 MiB 内测限制。"; return
        }
        let file = folder.appendingPathComponent(CameraDownloadPolicy.filename(suggestedFilename))
        downloadFile = file
        completionHandler(file)
    }
    func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) {
        decisionHandler(request.url.map(origin.allows) == true ? .allow : .cancel)
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard pendingDownload === download, let file = downloadFile, let folder = downloadFolder else { return }
        guard let values = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize,
              Int64(size) <= CameraDownloadPolicy.maxBytes else {
            clearPendingDownload(); status = "文件超过 64 MiB 内测限制。"; return
        }
        pendingDownload = nil; downloadFile = nil; downloadFolder = nil
        sharedFolder = folder
        sharedFile = SharedCameraFile(url: file)
        status = "下载完成，可保存到“文件”或分享。"
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard pendingDownload === download else { return }
        clearPendingDownload()
        status = "下载未完成，请重新点击下载。"
    }
    private func clearPendingDownload() {
        let download = pendingDownload
        pendingDownload = nil
        download?.cancel { _ in }
        if let folder = downloadFolder { try? FileManager.default.removeItem(at: folder) }
        downloadFolder = nil; downloadFile = nil
    }
    func removeSharedFile() {
        sharedFile = nil
        if let folder = sharedFolder { try? FileManager.default.removeItem(at: folder) }
        sharedFolder = nil
    }
}
