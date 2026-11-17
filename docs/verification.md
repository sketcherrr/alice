# 验证记录 · 2026-11-17

环境：Linux x64，Flutter 3.47.9。Rust 核心本轮未改动，使用先前构建并测试通过的动态库；本轮重新验证真实 FFI/SQLite 链路。

| 项目 | 结果 |
|---|---|
| Dart 静态分析 | 无问题 |
| 内存模拟 OpenAI 传输 | 通过：官方地址、Bearer Key、store=false、类型化回复、错误脱敏、禁止重定向、无 Key 不请求、不完整回复拒绝 |
| Agent 循环 + 实际 SQLite | 通过：严格函数定义、加密 reasoning 与 message phase 回传、call_id 对应、实际记忆检索、记忆建议不自动落盘、完整回复原子提交 |
| 工具异常与退出 | 通过：未知函数、无效 JSON/参数、重复 call_id、模型/工具次数上限、取消、revision 冲突、不成功的轮次不写聊天 |
| 上下文 | 通过：字节预算、完整对话对、有限旧对话摘录、长问题优先、删除记忆后旧聊天/摘录不再进入请求 |
| Flutter 无界面引擎 | 通过：初次选择、7 种动作场景、茶与小游戏、手动记忆、模型记忆建议确认、性格切换、反复关闭设置、模拟断网/取消保留草稿、重新打开 |
| 窗口尺寸 | 480×760、390×700、320×520，无布局或渲染错误；很小窗口可滚动 |
| 动画素材 | 3 个 RGBA 原图，合计 28 帧；透明通道保留，实际界面渲染检查通过 |
| Linux release | 重新编译成功，bundle 已包含本地核心、字体和动画图集，动态库依赖可解析 |
| 常规 flutter test | 环境禁止创建本地监听 socket，测试器启动失败；不能称该套测试通过 |
| 实际 OpenAI 账号调用 | 未执行，使用模拟传输，无真实 Key、无收费请求 |
| 操作系统桌面窗口/树莓派/其他平台真机 | 未验证；此次引擎检查不能替代这些测试 |
| 上次闪退的根因 | 未取得当时日志，不能确定根因；此次检查覆盖设置面板关闭、异步回复取消与重开等生命周期路径 |

## 复现

普通开发环境使用 `scripts/test.sh`。受限环境可以运行：

```bash
dart scripts/check-offline.dart
dart scripts/check-agent.dart
./scripts/check-ui.sh
```

`check-agent.dart` 只使用模拟 HTTP 与实际 Rust/SQLite。`check-ui.sh` 使用真实界面与本地核心，远程回复由测试专用传输模拟；不调用真实 OpenAI，也不发送真实 API Key。

当前环境恢复了临时 Flutter SDK 和校验过哈希的离线包缓存，直接使用 `flutter_tester --disable-vm-service` 运行 `lib/smoke.dart`。UI 验证入口不打进正式 release 应用。

## 实际渲染截图

- `artifacts/ui/companion-desktop.png`：简洁默认界面。
- `artifacts/ui/animation-happy.png`、`animation-tea.png`、`animation-sleeping.png`、`animation-thinking.png`：互动状态。
- `artifacts/ui/chat-desktop.png`：对话与待确认记忆入口。
- `artifacts/ui/companion-mobile.png`、`companion-small.png`：窄窗口。
- `artifacts/ui/memory-mobile.png`、`history-mobile.png`：按需展开的面板。

2026-11-06 原型验证记录中的 Rust 7 项测试已通过；本轮不把历史测试记为重新执行。旧版截图仍保留，以上文件为新版。

## macOS 通用测试包 · 2026-11-17

[成功的 CI 运行](https://github.com/sketcherrr/alice/actions/runs/44062425991)对应提交 `d92649a29aee89c23eac1c67927e8a12163b86ee`。环境为 macOS 15 ARM64、Xcode 16.4、Flutter 3.47.9、Rust 1.100.0。

| 项目 | 结果 |
|---|---|
| Release 构建与归档 | 成功生成 `Alice.app`，压缩包 36,741,818 字节 |
| 双架构与原生接口 | 主程序、Flutter 引擎、Dart AOT、Rust 核心均含 arm64/x86_64；四个 FFI 符号验证通过 |
| 签名与权限 | 深度严格签名检查通过，App Sandbox 与出站网络权限存在；当前为临时签名，未公证 |
| 资源 | 字体、角色立绘与三组动画图集检查通过 |
| 实际 Rust/SQLite | 通过 Dart isolate → 打包后的 dylib → SQLite，含中文存档与性格切换 |
| OpenAI 协议与 Agent | 模拟传输测试通过，包括 reasoning 回传、严格函数定义、真实记忆检索、取消、事务、上下文预算与删除记忆隔离 |
| Dart 静态分析 | 无问题 |
| Flutter 测试 | 9 项通过；包含 390、480、1280 宽度下的性格选择及互动/动画状态检查 |
| 取回后的压缩包 | GitHub 附件与应用 ZIP 哈希核对通过，CRC 完整性、双架构与 framework 符号链接检查通过 |
| 未覆盖 | Intel 原生运行、macOS 12 最低版本、Finder 人工启动/桌面体验、真实 OpenAI 账号调用 |

已修复打包校验脚本的 `lipo` 参数顺序；界面测试改为等到控件可以被点击后操作，避免持续动画与底部面板过渡导致误点。没有跳过失败检查。

应用 ZIP 的 SHA-256 为 `45127b3707c178036c4870368aba5f54105873debe571379e16e185250a1c1cd`。下载与首次打开步骤见 [macOS 测试说明](macos-testing.md)。
