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


## 透明桌宠与小游戏 · 2026-11-19

本轮新增原生透明桌面窗口、8 种动作（56 帧）和俄罗斯方块、打砖块，保留找珍珠。

| 项目 | 结果 |
|---|---|
| Rust 核心 | 8 项测试通过，包含成绩持久化、无效参数回滚及重复局 ID 不重复计次 |
| 规则引擎 | 独立 Dart 检查通过：七袋随机、旋转/消行/暂存/结束，挡板/砖块碰撞、三关与生命、暂停和帧率差异 |
| Dart 静态分析 | 无问题 |
| Linux release | GTK 原生透明窗口与 Flutter 界面编译通过，已更新随包 Rust 核心 |
| Windows release 编译 | [Windows CI](https://github.com/sketcherrr/alice/actions/runs/44455053215) 通过，包含 DWM/MethodChannel 原生代码；未交付带 Rust/SQLite 的 Windows 发行包 |
| 实际 Flutter 渲染 | 透明区域 alpha=0，角色存在；两种新游戏能打开、操作、暂停、关闭，无布局错误 |
| 渲染截图 | `artifacts/desktop-v2/transparent-desktop.png`、`tetris.png`、`breakout.png` |

本地引擎检查不能替代操作系统桌面人工体验；逐像素鼠标穿透未实现，Linux 透明显示取决于合成器。未执行真实 OpenAI 请求。

界面检查曾发现关闭面板后仍残留 220ms 窗口缩放任务；现改为可取消计时器，在新面板打开及界面销毁时取消，并加入销毁过程的回归检查。


[最终 macOS CI](https://github.com/sketcherrr/alice/actions/runs/44455053204)（源码 `e51da0c3b8b9ae40fee26cd1cf4421c52b32cd93`）通过全部 13 项 Flutter 测试与 8 项 Rust 测试；实际打包 dylib 的离线协议和 Agent 检查通过。四个二进制均有 arm64/x86_64 切片，签名、沙盒、联网权限与新旧动画资源验证通过。

已取回 0.2.0（build 2）应用 ZIP，41,616,983 字节。附件摘要、应用 SHA-256、CRC、双架构、framework 符号链接和 3 张新版图集与源素材一致性均已核对。应用 ZIP SHA-256：`8dd5e9451065951851587c10522e7171e57aac9d925125fc4ac3218a1ae53b8b`。下载见 [macOS 测试说明](macos-testing.md)。Mac/Windows 桌面显示、拖拽与多屏体验仍需真机人工测试。


## Lo-fi 与按住说话 · 2026-11-19

- 两首原创 MP3 的解码格式已核对：32kHz 立体声，长度约 50.5 秒与 56.5 秒；源脚本和 CC0 说明随源码提供。
- 独立语音协议检查通过：multipart 文件转写、Bearer 认证、重定向阻止、错误脱敏、Realtime 事件顺序、PCM/WAV 转换、连接取消与超时、不播放未完成音频。
- Linux 含播放/录音插件的 release 构建通过。新增声音面板经过实际 Flutter 引擎渲染检查，截图在 `artifacts/audio-v3/sound-panel.png`。
- 本机无界面渲染使用 Flutter patched kernel 编译器和 release 资源目录，避开受限环境下 Dart CLI 无法写入分析配置目录的问题；未修改 SDK 或应用代码来跳过检查。
- 没有真实 OpenAI Key，不进行收费请求；未在麦克风和扬声器上做真实录音/听音测试，实际中文音色、系统权限弹窗、回声与设备切换仍需真机验证。

完整的语音界面回归另在无界面引擎运行：模拟录音 → 转写 → 现有 Agent → 语音播放通过；录音结束文件迟到时切换应用不会继续上传。音乐、语音硬件和远端 API 在该检查中使用模拟实现。


[最终 macOS CI](https://github.com/sketcherrr/alice/actions/runs/44459600513) 对应源码 `1e06620f965fbf385d141b73e7832ceb649eeaa9`：22 项 Flutter 测试与 8 项 Rust 测试全部通过，实际 dylib 的离线协议与 Agent 检查通过。[Windows 编译](https://github.com/sketcherrr/alice/actions/runs/44459600588) 通过。完整语音界面测试等待原生窗口调整及设置弹窗输入框实际可交互后执行，没有跳过功能检查。

已取回 0.3.0（build 3）Mac 应用 ZIP，44,205,485 字节。附件与应用摘要、CRC、麦克风用途声明、两首音乐与源素材逐字节一致性、framework 符号链接均已核对。主程序、Flutter 引擎、Dart AOT、Rust 核心、objective_c 运行库共 5 个 Mach-O 二进制全部包含 arm64 与 x86_64。签名、Sandbox 出站联网和 audio-input 权限在 macOS CI 校验通过。

应用 ZIP SHA-256：`465ba33026febba4fad308d0e7ac7b7f2c4749733c3ce08001f3168abe26a67d`。本机副本为 `dist/Alice-macOS-universal-test.zip`，下载见 [macOS 测试说明](macos-testing.md)。

## 0.4 设备模式本地验证（2026-11-20）

- 11 项 Rust 测试通过，新增旧存档无损迁移、持续睡眠／重复操作、养成边界检查。
- Flutter 静态分析通过；Linux x64 release 构建通过，包括文件选择器及 D-Bus 配网代码。
- 真实 Flutter 无界面引擎＋Rust/SQLite 验证：设备画面、喂食／洗澡、睡眠跨重新打开恢复、欢迎语保存、待机／触摸唤醒、本地音乐导入／去重／恢复／删除以及 5GHz 与 2.4GHz 配置区分。截图在 `artifacts/device-v4/`。
- 原有离线、Agent、语音协议检查通过，均未调用真实 API。
- 自启动安装／移除及正常退出在临时目录中验证，未修改当前桌面的启动项。
- 标准 Flutter 测试命令在本环境无法监听 127.0.0.1，测试套件未在本机执行完成；不能将引擎检查冒充完整套件通过。
- 未操作当前系统的 Wi-Fi；未进行真实音频输出、5GHz 连接、ARM64／树莓派或 iPhone 测试。

最终云端验证：[macOS CI](https://github.com/sketcherrr/alice/actions/runs/44687261596)（源码 `faba4625284c516c901d75d1bc10d95cc6dc6e2a`）通过完整 **26 项 Flutter 测试、11 项 Rust 测试**及静态分析；[Windows CI](https://github.com/sketcherrr/alice/actions/runs/44687261574) release 编译通过。待机测试的真实异步文件 I/O 与模拟时钟冲突已修正，没有跳过测试。实际 macOS dylib 的离线协议／Agent 检查通过，应用签名及用户所选文件只读权限检查通过。

已取回并核对 0.4.0（build 4）Mac 测试应用：44,624,744 字节；附件摘要、ZIP CRC、五个二进制的 arm64/x86_64 切片、9 个符号链接、内置音乐与角色资源一致性检查通过。应用 SHA-256：`ea8be087e3ed6be1e206b8e130a6bf0cee60409aec863e903226490d3d27f959`。Linux x64 预览包在 `dist/Alice-linux-x64-device-test.tar.gz`，SHA-256：`2d84b60c7281e547c31c2f1f6a6f93966d9362487427d7119d7b2fe23bd747e6`。
