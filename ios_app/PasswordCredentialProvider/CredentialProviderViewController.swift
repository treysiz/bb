import AuthenticationServices
import UIKit

final class CredentialProviderViewController: ASCredentialProviderViewController, UITableViewDataSource, UITableViewDelegate {
    private var records: [VaultRecord] = []
    private var pendingSave: ASSavePasswordRequest?
    private let titleLabel = UILabel()
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let messageLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0
        messageLabel.textColor = .secondaryLabel
        table.dataSource = self; table.delegate = self
        cancelButton.setTitle("取消 / 忽略", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        saveButton.setTitle("保存到 MiniBridge 密码库", for: .normal)
        saveButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        saveButton.addTarget(self, action: #selector(savePending), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel, saveButton, table, cancelButton])
        stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            table.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
        saveButton.isHidden = true
    }

    override func prepareInterfaceForExtensionConfiguration() {
        titleLabel.text = "连接 MiniBridge 密码库"
        messageLabel.text = "请先打开 MiniBridge Password App，输入 HTTPS 服务器地址、一次性配对码和密码库主密码。完成后重新打开此自动填充界面。"
        table.isHidden = true
    }

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        pendingSave = nil; saveButton.isHidden = true; table.isHidden = false
        titleLabel.text = "选择要填入的账号"
        guard let service = serviceIdentifiers.first else { messageLabel.text = "无法识别当前网站或 App。"; return }
        let identifier = service.type == .app ? "app:" + service.identifier : service.identifier
        Task {
            do {
                records = try await VaultRepository.shared.records(for: identifier)
                messageLabel.text = records.isEmpty ? "此网站或 App 没有匹配的密码。" : "选择一个账号后，使用 Face ID 或设备密码确认。"
                table.reloadData()
            } catch { messageLabel.text = "无法读取密码库。请确保已配对、联网，并完成 Face ID/设备密码验证。" }
        }
    }

    override func prepareInterface(for savePasswordRequest: ASSavePasswordRequest) {
        pendingSave = savePasswordRequest; table.isHidden = true; saveButton.isHidden = false
        titleLabel.text = "保存登录密码？"
        messageLabel.text = "\(savePasswordRequest.serviceIdentifier.identifier)\n账号：\(savePasswordRequest.credential.user)\n\n选择保存后，密码会加密并加入 MiniBridge 密码库。"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { records.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let record = records[indexPath.row]
        cell.textLabel?.text = record.title; cell.detailTextLabel?.text = record.username
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let record = records[indexPath.row]
        extensionContext.completeRequest(withSelectedCredential: ASPasswordCredential(user: record.username, password: record.password), completionHandler: nil)
    }

    @objc private func savePending() {
        guard let request = pendingSave else { return }
        messageLabel.text = "正在加密并保存…"; saveButton.isEnabled = false
        Task {
            do {
                try await VaultRepository.shared.save(site: request.serviceIdentifier.identifier,
                    username: request.credential.user, password: request.credential.password,
                    title: request.title, isApp: request.serviceIdentifier.type == .app)
                extensionContext.completeSavePasswordRequest(completionHandler: nil)
            } catch { messageLabel.text = "保存失败。请确认网络、服务器 TLS 和密码库解锁状态，然后重试。"; saveButton.isEnabled = true }
        }
    }

    @objc private func cancel() {
        extensionContext.cancelRequest(withError: ASExtensionError(.userCanceled))
    }
}
