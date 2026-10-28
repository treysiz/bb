# MiniBridge 摄像 iOS 内测版

目标：先在 iPhone 上验证现有 NAS 的会员登录、实时摄像、伴音、多人观看和重连。App 使用 SwiftUI + WKWebView，复用现有服务器权限，不改 NAS 数据和 ESP 固件。

当前仅完成源码与 Windows 可执行检查；**不是已签名 IPA，也未安装到 iPhone**。当前电脑没有 Xcode 或 Swift 编译器，原生编译、签名、Swift 策略测试、TestFlight 上传、真机摄像与声音验证均为 NOT_RUN。工程入口为 `ios_app/MiniBridgePassword.xcodeproj`，选择新共享 Scheme **MiniBridge Camera**。原密码库 App 和 AutoFill 扩展保留，新摄像 target 不依赖它们、不需要 AutoFill/共享钥匙串权限。

## 第一版范围

- 默认连接 `https://zhangjunqiao.duckdns.org:18443`；用现有会员账号登录，不内置密码或设备令牌。设置只保存 HTTPS 服务器地址。
- 浏览器原有的设备隔离、超级管理员管理、摄像伴音授权和多人观看继续由 NAS 强制执行。
- iOS 16 及以上，支持竖屏、横屏、页面内全屏和手动刷新；回到前台只尝试重连摄像控制，不自动启动画面或声音。
- 切入后台时尽力停止本页手动采集/播放并锁定网页密码库，NAS 自动移动监测不受影响。iOS 可能立即挂起进程，仍由服务器保留原有超时保护；不承诺锁屏后继续播放。
- 接入网页确认对话框和同源下载的系统保存/分享入口，单次只处理一个下载；已知大小先检查，完成后复查，内测上限 64 MiB。未知长度下载仍需真机检查磁盘/失败行为。临时文件使用独立随机目录，分享关闭后清理。
- 拒绝网页使用 iPhone 摄像头/麦克风；ESP 声音播放不需要这些本地采集权限。未加入后台音频、APNs 推送或系统 VPN 扩展。
- 顶层导航、下载及下载重定向限制到配置服务器的 HTTPS 主机与端口；同源 blob 下载允许，外链仅在用户主动点击 HTTPS 链接时交给系统浏览器。证书由系统正常验证，无 HTTP 放行和不可信证书绕过。
- WKWebView 使用默认持久网站数据存储；登录仍采用后台当前标签页的 sessionStorage 机制。普通刷新与强制结束 App 后的会话行为需分别实测；进程被系统回收后可能需要重新登录，不将默认持久数据存储等同于永久保存登录令牌。

## 在 Mac 构建和安装

没有 Mac 时，可使用已准备的云端无签名编译流程，参见 docs/IOS_CLOUD_BUILD.md。云端任务尚未运行；上传源码到公开仓库前需单独取得许可。
用户目前只有免费开发者账号；自己的手机测试可尝试 Windows 个人重签路线，见 docs/IOS_PERSONAL_INSTALL_WINDOWS.md，不使用 TestFlight 分发。

需要可用的 Mac/Xcode；具体 Xcode 版本须支持测试 iPhone 的系统版本。先把源码压缩包复制并解压到 Mac，不要只复制 `.xcodeproj` 目录。

1. 打开 `ios_app/MiniBridgePassword.xcodeproj`，Scheme 选 **MiniBridge Camera**，不要选旧的 Password/AutoFill Scheme。
2. 在新 target 的 Signing & Capabilities 中选择自己的 Team；将默认 `com.minibridge.camera` 改成自己账号下唯一的 Bundle Identifier。
3. 连接 iPhone，按 Xcode/手机提示启用开发者模式并信任设备，选择 iPhone 后 Run。本机设备测试可使用个人 Apple Account；免费个人 Team 的限制以 Xcode 当前提示为准。
4. 先跑核心策略测试：`swift test --package-path ios_app/CameraCore`。这些测试覆盖 HTTPS 地址输入、主机/端口隔离、同源 blob 及安全文件名。
5. 可选模拟器编译：`sh scripts/build_ios_camera.sh simulator`。这不是摄像/拾音真机验收。
6. 已在 Xcode 配置好签名后，可归档：`sh scripts/build_ios_camera.sh archive YOUR_TEAM_ID YOUR_UNIQUE_BUNDLE_ID`。脚本不上传、不创建 Apple 账号、不自动修改签名门户；归档在 `firmware/build/ios-camera/`。

如果需要通过 TestFlight 安装，使用已加入 Apple Developer Program 的账号，在 Xcode Organizer 选择归档并上传 App Store Connect，再创建内部测试组并邀请测试者。苹果所称“内部测试者”是有对应访问权限的 App Store Connect 用户；普通会员测试应按外部测试流程处理，不能把内部账号权限随意授予所有会员。外部首次测试版本可能需要 Beta 审核。TestFlight 构建最多测试 90 天；上传所需 SDK/Xcode 版本以苹果当前要求为准。[分发方式](https://help.apple.com/xcode/mac/current/en.lproj/dev31de635e5.html)、[个人设备测试](https://developer.apple.com/help/account/membership/program-enrollment)、[内部测试者](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)、[TestFlight](https://developer.apple.com/testflight/)。

## 第一轮 iPhone 验收（尚未执行）

| 项目 | 操作与通过条件 | 状态 |
|---|---|---|
| 登录与刷新 | 登录已有会员，刷新 App 页面后仍可访问原工作区；退出后旧会话失效 | NOT_RUN |
| 摄像画面 | 同一设备分别测试 720p、1080p，观察清晰度、首帧与播放稳定性；不将目标帧率当成实测 | NOT_RUN |
| 伴音 | 自动监测预览目前为无声；先由有权限的人暂停自动监测，再在手动摄像勾选伴音，确认听到 ESP 侧声音。测试完成恢复原监测设置 | NOT_RUN |
| 权限 | 未授予伴音的会员只能看无声画面；独立远程拾音仍限超级管理员 | NOT_RUN |
| 多人观看 | App 与电脑用两个有设备权限的账号同时看同一设备；一人停止/退出，另一人继续 | NOT_RUN |
| 横屏与手机布局 | 横竖屏切换、页面内全屏、刘海/底部区域均无挡住按钮或横向溢出 | NOT_RUN |
| 后台和锁屏 | 切到其他 App/锁屏后本页播放结束；NAS 监测继续；返回可重连控制但不会自行开始采集 | NOT_RUN |
| Wi-Fi/流量切换 | 断网后恢复网络，用重新连接恢复；不要求重启 ESP | NOT_RUN |
| 文件 | 录音/录像下载可保存到“文件”；仅用专门创建的测试片段验证删除与批量删除确认，不删除原有用户记录 | NOT_RUN |
| App 进程回收 | 强制结束后重开，记录是否需重新登录；不能将 sessionStorage 丢失误报为服务器撤销账号 | NOT_RUN |
| 长时与隐私 | 连续观看及多次开始/停止，无意外本地采集权限请求；手动采集仍受现有 10 分钟上限约束 | NOT_RUN |

官方接口依据：[WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore)、[内联播放](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/allowsinlinemediaplayback)、[播放手势](https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/mediatypesrequiringuseractionforplayback)、[WebKit 下载](https://developer.apple.com/documentation/webkit/wkdownloaddelegate)、[本地采集权限](https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:requestmediacapturepermissionfor:initiatedbyframe:type:decisionhandler:))。
