# 没有 Mac 时的 iOS 编译路线

用户已确认没有 Mac。先用 GitHub Actions 的 macOS 托管 runner 验证 Swift/Xcode 编译，再配置账号签名与 TestFlight；无签名编译成功不等于已有可安装 IPA。

本项目已准备 `.github/workflows/ios-camera-check.yml`：

1. 手动触发，或向 `ios-camera-test` 分支提交相关源码时触发。
2. 使用 `macos-15-intel`，最多运行 25 分钟；只读仓库权限，不持久保存 checkout 凭据。
3. 执行工程元数据测试、实际生命周期 JavaScript、Swift HTTPS/下载策略测试。
4. 分别编译模拟器与 iPhone SDK，显式关闭代码签名。
5. 构建成功后，将经过 iPhoneOS/ARM64 平台验证的真实输出打包为明确标注 `UNSIGNED-resign-required` 的 IPA，并保留 7 天构建产物；它仅供 Windows 个人重签，不是可直接安装或 TestFlight 包。不读取 Apple 签名密钥、不连接 NAS 或启动摄像头。

当前本地未配置 Git remote；GitHub 连接只发现公开仓库 `treysiz/bb`。**尚未上传本项目，也未触发云端任务**。上传到该仓库会公开上传的源码，必须取得用户明确许可；优先使用由用户指定并授权的私有仓库。不默认公开代码，也不购买云服务。公共标准 runner 与私有仓库配额/收费规则不同，应按仓库账号当前设置核对。[GitHub runner 说明](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。

后续安装方式：

- **有 Apple Developer Program 会员**：可准备签名构建并通过 TestFlight 分发。证书/描述文件或 API 私钥应放入用户授权的 CI Secrets；不要发在聊天或提交到 Git。签名流程是单独阶段，当前 workflow 不含它。[Apple 分发要求](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)、[GitHub 签名凭据说明](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)。
- **只有普通 Apple ID**：不能用它进行 TestFlight 分发。可尝试云端构建后在 Windows 用 AltStore Classic 进行个人重签，通常每 7 天续签一次；详见 docs/IOS_PERSONAL_INSTALL_WINDOWS.md。无签名 IPA 本身不能直接安装。[Apple 个人 Team 限制](https://developer.apple.com/help/account/basics/about-your-developer-account)。
- 如果暂时不办理开发者会员，可以继续用已有 Safari 后台测试摄像和声音，或在用户选择后制作主屏幕 Web App；它们不等于已交付原生 App。

用户已确认仅有免费开发者账号、没有 Mac；目标仓库与源码上传许可仍待明确。云端编译、签名、iPhone 安装和媒体验收仍为 NOT_RUN。原生源码与安装步骤见 docs/IOS_CAMERA_TESTFLIGHT.md。
