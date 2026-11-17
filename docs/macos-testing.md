# macOS 测试版构建

交付目标是一个可直接运行的 `Alice.app`，测试者不需要安装 Xcode、Flutter 或 Rust。当前准备的是构建流程；在 macOS runner 成功执行前，不把源码压缩包称作 Mac 应用。

## 当前状态

- Linux 工作机没有 Xcode，无法执行 Flutter macOS 编译。
- 已补齐 macOS 核心 dylib 装配、运行时查找路径、Foundation 存档目录、出站联网权限和 480×760 窗口。
- 已准备 Apple Silicon + Intel 通用应用的构建、嵌套代码签名、资源/架构校验和 GitHub Actions 工作流。
- 尚未在 Mac 编译或运行，也尚未得到真实 `.app`。
- `dist/Alice-macOS-build-input.zip` 只是供构建机使用的源码与素材输入，不能当作应用安装。它排除了 Key、用户存档、本机构建目录和 SDK 缓存。

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

必须先确定并授权一个用于存放此项目代码的仓库，才能上传代码并运行。本轮没有上传到任何外部仓库。

## 测试者拿到应用后

解压最终 **universal-test** 压缩包，将完整 `Alice.app` 拖到“应用程序”后打开。在右上角抽屉配置自己的 OpenAI Key 和模型 ID；Key 不随构建包提供。

这是临时签名的内部测试版，尚未使用 Developer ID 签名或经 Apple 公证。macOS 可能要求在“系统设置 → 隐私与安全性”中确认允许打开。正式公开发布前需单独完成签名、公证和安装分发验证，不通过脚本修改系统安全设置。

建议测试初次选择性格、摸摸/喝茶/休息动画、关闭后重开存档、API 聊天、取消请求、确认/删除记忆，以及屏幕缩放和窗口调整。

存档通过 Foundation 的 Application Support 定位，在 App Sandbox 的容器内创建 Alice 目录；不写入 `.app` 内。Finder 启动不依赖终端的当前目录。

参考：[Flutter 的 macOS 环境要求](https://docs.flutter.dev/platform-integration/macos/setup)、[macOS 发布](https://docs.flutter.dev/deployment/macos)、[Apple 出站联网权限](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client)、[GitHub 托管 runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。
