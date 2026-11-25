# macOS 测试版构建

已交付 0.4.1 可直接运行的 `Alice.app`（新增系统代理读取、手动 HTTP 代理与连接诊断；包含离线养成、本地音乐导入、lo-fi 与按住说话），测试者不需要安装 Xcode、Flutter 或 Rust。

## 当前状态

- 2026-11-25 在 GitHub macOS 15 / ARM64 构建机成功生成 Apple Silicon + Intel 通用应用；[构建与测试记录](https://github.com/sketcherrr/alice/actions/runs/45602983312)。
- 应用对应源码提交 `59294db9adc19148fcb66f25a7cf636165768084`，版本 0.4.1 / build 5，使用 Flutter 3.47.9。
- 已验证双架构、嵌套签名、字体/动画、FFI 导出、沙盒、出站联网、麦克风及用户所选文件只读权限；静态分析无问题，30 项 Flutter 测试与 15 项 Rust 测试通过，实际 Rust/SQLite、模拟 OpenAI Agent 与代理检查通过。新增测试包含真实本地 HTTP 代理转发、模型读取检查、错误详情展示与关闭检查时取消请求。
- 已下载并再次核对附件哈希、应用压缩包完整性、五个二进制（含 objective_c 音频依赖）的架构切片与 9 个 framework 符号链接。用户已确认旧版 Mac 基础功能正常；新版系统代理与真实 API、Intel 真机及最低系统版本仍待测试。未调用真实 OpenAI API。
- [下载测试附件](https://github.com/sketcherrr/alice/actions/runs/45602983312/artifacts/15017550354)，需登录 GitHub，保留至 2026-12-09。附件内包含应用压缩包及 SHA-256 文件；本地副本位于 `dist/`，原本的旧包已另存保留。

`Alice-macOS-universal-test.zip` 的 SHA-256：

```text
325543588687130bff7e1d1a1f6f43287c1b50433f349fdb3f630322a1e5bead
```

旧的 `dist/Alice-macOS-build-input.zip` 只是源码与素材输入，不能作为应用安装。

## 在 macOS 构建机生成应用

使用 macOS、完整 Xcode、Flutter 3.47.9、Rust/rustup 和 Python 3。第一次应在构建机完成 Xcode 初始化及许可确认。

```bash
./scripts/build-macos.sh
```

该脚本会安装两个 Rust macOS target，生成 Flutter 资源，构建通用 `.app`。Xcode 的 `Build Alice Core` 阶段编译对应架构的 Rust dylib，合并后放入 `Contents/Frameworks` 并先签名嵌套代码；之后由 Xcode 签名整个应用。应用使用系统 SQLite，不依赖测试者的 Homebrew。

打包前会验证主程序、Flutter 引擎、Dart AOT 程序和 Rust 核心均有 `arm64`、`x86_64` 两个架构；验证四个 FFI 导出、字体、动画资源、签名及 sandbox/network.client 权限。通过实际 dylib 运行离线对话协议和 Agent 测试后，生成：

- `dist/Alice-macOS-universal-test.zip`：解压得到 `Alice.app`。
- `dist/Alice-macOS-universal-test.zip.sha256`：校验值。

目标最低系统版本为项目当前配置的 macOS 12.0；实际兼容范围还需目标机器验证。CI 在其宿主架构运行测试，另一架构只检查切片与导出符号，不能据此声称双架构真机验证完成。

## GitHub Actions

工作流：`.github/workflows/macos-test.yml`，名称 `macOS test app`，在 `macos-15` runner 上执行。

- Flutter 固定为 3.47.9，下载官方 SDK 并校验 SHA-256。
- checkout/upload-artifact 固定到已查询的提交 SHA，workflow 仅有 contents:read 权限。
- 不需要 OpenAI Key、Apple 开发者证书或仓库写入凭据。
- 编译、包结构校验、离线协议检查和 Flutter 测试成功后才上传应用压缩包；不自动发布 Release。
- 可以手动启动，也可由 main/master、`build/macos-test/**` 分支的相关代码提交或 PR 触发。
- 最长运行 45 分钟，构建产物保留 14 天；使用该 GitHub 账户的 Actions 配额。

源码与工作流已上传至用户指定的 [sketcherrr/alice](https://github.com/sketcherrr/alice)。附件过期后，可从 Actions 的 `macOS test app` 工作流手动重新构建。

## 测试者拿到应用后

从 GitHub 下载时先解压附件，再解压其中的 `Alice-macOS-universal-test.zip`；使用本地 `dist/` 中的同名应用压缩包时只需解压一次。将完整 `Alice.app` 拖到“应用程序”后打开。右键人物打开抽屉，在「连接 OpenAI」中配置自己的 OpenAI Key 和聊天模型 ID；Key 不随构建包提供。音乐按钮可直接离线播放，麦克风按钮用于按住说话；首次录音需允许麦克风权限。「声音小窝」可试听音色和调整音量。

### 0.4.1：使用 Clash／Surge 等系统代理连接 OpenAI

旧版只读取终端的代理环境变量，未接入 macOS 系统代理设置。因此从 Finder 双击启动时，即使浏览器能连接，Alice 也可能无法联网。0.4.1 在「自动」模式中读取系统对 OpenAI 地址的 HTTP(S) 代理配置；聊天、录音转写和语音回复共用连接方式。

1. 退出旧版 Alice，替换应用后重新打开；正常运行代理软件。
2. 在「连接 OpenAI」填写自己的官方 Key、账号可用的模型 ID；连接方式先选「自动（系统／环境代理）」。
3. 点击「检查连接」。成功后会显示采用的连接方式，再点「保存设置」并发一句简短消息。检查只调用模型读取接口，不生成回复；聊天权限与额度仍须通过实际聊天验证。
4. 如果提示 PAC／SOCKS，选择「手动 HTTP 代理」，填写代理软件实际的 HTTP／混合端口，例如 `http://127.0.0.1:7890`。示例端口不一定适用，不要填写订阅地址或 SOCKS 端口。
5. 若仍失败，复制界面中的诊断文字，包括 HTTP 状态、错误码和 Request ID（若有）。请勿发送 Key。上次聊天失败详情也可在此窗口重新查看。

Key 和手动代理配置仅保留到退出应用。自动模式优先遵循代理环境变量及其 `NO_PROXY` 例外，再查询系统设置；PAC 脚本、SOCKS 和需要认证的代理暂不直接支持。连接失败不会关闭 TLS 验证或自动改为直连。

需要真机补测：Finder 启动后的系统代理聊天；手动 HTTP／混合端口；关闭代理时的诊断；重新启用后恢复；同一路径下的录音转写和语音回复。CI 使用模拟服务，不验证个人 Key、账户权限或真实代理规则。

这是临时签名的内部测试版，尚未使用 Developer ID 签名或经 Apple 公证。macOS 可能要求在“系统设置 → 隐私与安全性”中确认允许打开。正式公开发布前需单独完成签名、公证和安装分发验证，不通过脚本修改系统安全设置。

建议测试透明桌面背景、拖动/双击/右键人物、操作条自动收起、初次选择性格、八种动画、三种小游戏与最高分、切换应用时暂停、关闭后重开存档、API 聊天、取消请求、确认/删除记忆，以及多屏和显示缩放。新增检查项：两首 lo-fi 的循环与切换、麦克风权限、按住/松开/移出取消、真实语音转写、中文音色与停止播放、音乐压低与恢复。

存档通过 Foundation 的 Application Support 定位，在 App Sandbox 的容器内创建 Alice 目录；不写入 `.app` 内。Finder 启动不依赖终端的当前目录。

参考：[Flutter 的 macOS 环境要求](https://docs.flutter.dev/platform-integration/macos/setup)、[macOS 发布](https://docs.flutter.dev/deployment/macos)、[Apple 出站联网权限](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)、[GitHub 托管 runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。

0.4 新增人工测试项：导入／移除本地音乐、定时暂停、喂食／洗澡、睡眠跨重启恢复。首次打开前建议备份整个 Alice 数据目录；schema 2 存档无法由 0.3 打开。原生全屏设备窗口及配网入口目前仅在 Linux 接入。
