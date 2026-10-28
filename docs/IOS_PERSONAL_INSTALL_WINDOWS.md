# 用免费账号在自己的 iPhone 内测

用户已确认：没有 Mac，有免费 Apple 开发者账号，尚未加入付费 Developer Program。优先验证自己的手机，不以 TestFlight 分发给会员。

当前状态：源码工程和云端流程已准备，**没有编译好的真实 IPA，不能把源码 ZIP 直接安装到 iPhone**。源码上传仓库的公开/私有选择仍待明确，尚未上传或运行云编译。

## 原生测试路线

1. 用户明确授权源码存放仓库。当前连接可用的 `treysiz/bb` 是公开仓库；使用它会公开 iOS 源码和预设 NAS 域名，不能从含糊的“好”推断用户已选择公开。也可由用户新建并授权私有仓库。
2. 云端 Mac 运行 Swift 策略测试和 Xcode 模拟器/iPhone 构建。只有 iPhone 构建成功，才运行 `scripts/package_ios_camera_ipa.py`；导出 `MiniBridge-Camera-0.2.0-UNSIGNED-resign-required.ipa` 及 SHA256 清单。
3. 该 IPA 是**待个人重签名的输入**，并不是已签名安装包。打包器验证 iPhoneOS/ARM64 Mach-O 平台，拒绝将模拟器输出改名为手机包，不包含签名证书或描述文件。云端不需要 Apple ID 或 Apple 签名密钥。
4. 在用户自己的 Windows 上按 AltStore Classic 官方步骤安装 AltServer/AltStore，使用 USB 连接并信任自己的 iPhone，按手机提示启用开发者模式。Apple 登录和验证码由用户在本机完成，不发送到聊天或 GitHub。[Windows 安装说明](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)。
5. 下载云端构建产物，核对文件名和哈希，使用 AltStore Classic 导入 IPA，由用户的账号重签并安装；具体手机系统与 AltStore 版本兼容性尚未实测，不保证首次安装一定成功。源码本身没有需要付费 entitlement 的 AutoFill 扩展依赖。
6. 开启 MiniBridge，使用原有 NAS 会员账号登录，按 docs/IOS_CAMERA_TESTFLIGHT.md 的验收表测试摄像和声音。自动移动监测的预览原本无声；伴音测试需有权限并切到手动摄像，测试后恢复原有监测设置。

免费个人签名通常 7 天到期，需续签；每个设备最多 3 个此类 App，AltStore 自身也占用名额。AltStore 可在能连接 AltServer 时尝试刷新，但不要将它视为永久安装。它不能替代面向会员的 TestFlight/App Store 分发。[Apple 免费个人 Team 限制](https://developer.apple.com/help/account/basics/about-your-developer-account)、[AltStore 刷新说明](https://faq.altstore.io/altstore-classic/your-altstore)。

若只是立即预览已有手机网页效果，可以用 iPhone Safari 打开 `https://zhangjunqiao.duckdns.org:18443`，通过“分享 → 添加到主屏幕”建立入口。这使用已有移动网页，**不是上述原生内测 App 的安装或验收**。

## 当前未执行项目

云端上传/编译、真实 IPA 生成、AltServer 下载/安装、Apple 登录、重签、手机安装、视频/伴音实测均为 NOT_RUN。未读取账号密码或配对资料，未修改 iPhone、Windows 软件、NAS 或 ESP。合成 IPA 打包测试只在临时目录执行并清理，不能当成真实安装包交付。
