# Alice · 小小鲸屿

一个本地优先的角色伙伴原型：以单一角色为中心的简洁陪伴窗口，三种可选性格、离线互动、长期记忆与 OpenAI Agent 文字对话。

**[去小小鲸屿坐坐 →](https://sketcherrr.github.io/alice/)** · 项目介绍、角色互动预览与下载入口。网页源码位于 [website/](website/README.md)，由 GitHub Pages 自动发布。

当前源码为 **0.4.1 连接修复版**，新增 macOS 系统 HTTP(S) 代理读取、手动 HTTP 代理、模型连接检查与可保留的错误详情。包含 0.4 的树莓派全屏布局、待机与欢迎、离线养成、音乐导入及双频配网。ARM64 构建和真实树莓派连接仍待验证。

当前完成 Linux 桌面原型，并已在 macOS CI 构建出 Apple Silicon + Intel 通用测试应用；静态分析、26 项 Flutter 测试及实际 Rust/SQLite 检查通过。Mac 桌面人工体验仍待测试。Windows、Android、iOS 已有 Flutter 平台工程，原生库打包、移动端数据目录及真机验证尚未完成；不能把这些工程视为已发布的平台版本。

## 现在可以做什么

- 首次选择「温柔但有主见」「聪明、略带俏皮」「慢热、细腻而克制」。
- 展示生图生成的鲸鱼主题角色，包含待机眨眼、挥手、倾听、思考、开心、喝茶、睡眠、伸懒腰 8 组动作（共 56 帧），带呼吸、动作淡入衔接及互动小特效。
- 喂点心、洗泡泡澡、持续睡眠／唤醒、喝茶、安静陪伴、找珍珠、俄罗斯方块、打砖块；完全离线可用，新小游戏最佳成绩保存在本机。
- 小岛电台：两首内置原创 lo-fi，离线循环播放、切歌和音量调节。
- 按住说话、松开发送，识别后接入原有聊天与记忆流程；AI 合成的卡通女生声音有轻甜、元气、轻声三档，支持试听与自动朗读。录音时静音音乐，说话时降低音乐音量。
- SQLite 自动保存性格、状态、活动和聊天；重新打开恢复。
- 在抽屉面板添加、查看和删除长期记忆；模型可提出记忆建议，经你确认才保存。切换性格保留记忆、聊天和养成进度。
- 配置 OpenAI API Key 与账号可用的模型 ID 后，使用 Responses API 进行文字聊天，支持记忆检索、状态读取、表情安排和待确认记忆的函数调用循环。
- 没有 Key、断网、超时或 API 返回错误时，保留输入，小屋继续可用。

本轮不包含摄像头、屏幕理解、无需确认的自动记忆保存、云同步和正式发行签名/公证。这些是后续阶段，不显示成已经可用的按钮。

## 在 Linux 上启动

**Cardputer-Adv 首轮测试**：新增 PlatformIO 小屏固件，通过 SSH 使用 Arch 主机上的 Rust／SQLite 核心。包含喂食、洗澡、睡眠、摸头、找珍珠与断线后恢复；安装、配网和上传步骤见 [Cardputer 测试指南](docs/cardputer.md)。设备本身只支持 2.4 GHz Wi-Fi；这个客户端尚未移植在线聊天、语音和独立离线养成。

如果已有构建产物：

```bash
./scripts/run-linux.sh
```

没有构建产物时，该脚本会调用构建脚本。开发依赖：Rust/Cargo、Flutter（本轮验证版本 3.47.9）、Clang、CMake、Ninja、pkg-config、GTK 3 开发库、SQLite 3 开发库、GStreamer 开发库、Python 3。Linux 录音还需要 `parecord`、`pactl`、`ffmpeg` 和可用的声音设备。

```bash
./scripts/build-linux.sh
./scripts/run-linux.sh
```

可执行程序位于 `apps/companion/build/linux/x64/release/bundle/alice_companion`。移动程序时需要带上整个 `bundle` 目录，不能只复制单个可执行文件。目标系统需要兼容的 GTK 3、SQLite 和系统运行库。

树莓派计划使用 64 位 Linux，在目标机器上构建 ARM64 版本，复用同一角色核心；显示、触摸、音频和性能仍需树莓派真机验证。

## 后续填写 API Key

右键人物打开抽屉，或将鼠标停在人物上再点「…」→「连接 OpenAI」，填写自己的 API Key 和账号可用的模型 ID。密钥仅保留在本次应用进程内，不写入 SQLite，不写入日志。关闭应用后需要重新填写。

也支持从启动环境读取 `OPENAI_API_KEY` 与 `OPENAI_MODEL`，本项目不会自动读取 `.env` 文件。不要把密钥写进代码、截图或版本库。默认不内置模型 ID，避免将某个账号无权使用或已下线的型号固定在产品里。

请求发送至 `https://api.openai.com/v1/responses`，带有当前性格、相关记忆、近期活动和最近对话。设置 `store: false` 表示不使用 Responses 持久会话功能，不代表供应商完全不保留请求数据。当前为非流式文字回复，不会自动重试收费请求。

**Mac 浏览器能访问、Alice 连接失败时**：旧版从 Finder 启动时可能没有终端中的代理环境变量。0.4.1 的「自动」连接方式会优先使用代理环境变量，随后读取 macOS 对该 API 地址的系统 HTTP(S) 代理配置；文字聊天、录音识别与语音回复共用此设置。若使用 PAC 或 SOCKS，当前会明确提示改选「手动 HTTP 代理」，填写代理软件实际的 HTTP／混合端口，例如 `http://127.0.0.1:7890`；示例端口不一定是你的端口。不会关闭 TLS 证书校验，也不会在配置不可用时偷偷绕过代理。

填写 Key 和模型 ID 后可点「检查连接」：它只调用 `GET /v1/models/{model}` 读取模型信息，不发送聊天、记忆或录音，不生成回复。检查成功说明网络和模型读取已通，不保证聊天端点权限或生成额度；受限 Key 也可能允许聊天而禁止读取模型。错误会显示 HTTP 状态、可识别的错误码和经过筛选的 Request ID，区分 `insufficient_quota`、`rate_limit_exceeded`、`model_not_found`、TLS/网络失败。原始服务器错误文本不显示，以免回显 Key 或私密输入。上一次聊天失败的详情可再次打开「连接 OpenAI」查看。

Key 与手动代理设置都只保留在本次启动内；更换 Key 不会自动发起连接检查。参见 [OpenAI 错误码](https://developers.openai.com/api/docs/guides/error-codes) 与 [模型读取接口](https://developers.openai.com/api/reference/resources/models/methods/retrieve)。

资料参考：[Responses API 官方说明](https://developers.openai.com/api/docs/guides/migrate-to-responses)。

## 数据与记忆

Linux 默认存档：`${XDG_DATA_HOME:-$HOME/.local/share}/alice/companion.sqlite3`。可用 `ALICE_DATA_DIR` 指定其他目录。首次运行不自动选择性格。

- 目前保留最近 200 条聊天、100 条活动，以及最多 100 条用户确认的长期记忆。
- 上下文保留最多 10 轮完整近期对话、8 条相关记忆、5 条活动，并按字节预算自动裁剪；旧对话使用受限的原文摘录。
- 删除记忆时，删除前的聊天上下文停止发送给模型，避免旧对话把被删事实带回来；界面仍保留可查看的历史聊天。
- 切换性格会重新开始对话上下文，避免旧性格的语气影响新回复；历史记录与长期记忆保留。
- 没有自动生成事实摘要或向量索引，也不会把示例对话写成用户的真实经历。
- 未实现跨设备同步、账号、存档导入或加密备份。

## 检查

普通开发环境：

```bash
./scripts/test.sh
```

不允许本地监听端口的环境，可运行独立检查：

```bash
cargo test --locked
cargo build --release --locked
dart scripts/check-offline.dart
dart scripts/check-agent.dart
./scripts/check-ui.sh
```

`check-offline.dart` 用内存模拟 HTTP 客户端验证 OpenAI 请求、回复解析、错误处理和凭据处理，不调用真实 API；同时检查真实 Dart → Rust → SQLite 链路。

`check-ui.sh` 使用 Flutter 无界面引擎加载实际界面和真实 Rust 核心，检查选择、互动、小游戏、记忆和性格切换，输出桌面与窄屏截图至 `artifacts/ui/`。当前脚本的引擎路径针对 Linux x64。

## 美术与字体

- 原始角色：`assets/characters/alice/idle.png`，透明 PNG。
- 使用内置 `image_gen` 生图，完整提示词与生成方式保存在 `assets/characters/alice/artwork.json`。
- 以鲸鱼娘的蓝白海洋视觉为参考设计原创角色，没有品牌文字。逐帧动画源文件位于 `assets/characters/alice/animations/`，完整动画提示词保存在该目录的 `generation.json` 与 `generation-v2.json`。原始立绘保留作为加载失败时的后备。
- 字体为 Noto Sans CJK SC，附带 `assets/fonts/OFL.txt`。独立字面从本机 Noto CJK 字体集合提取，字形未修改。
- `scripts/prepare-assets.py` 将源资源复制到 Flutter 资源目录，不改变图片透明度。

桌面版默认透明、无标题栏、置顶。闲置后只留下角色；鼠标移到角色上会显示操作条，拖动角色可以移动窗口，双击打开聊天，右键或长按打开抽屉。设置、记忆、三种小游戏、取消置顶和退出入口均在抽屉中。聊天和面板关闭后窗口缩回。非桌面平台继续使用小屋界面。

架构说明见 [docs/architecture.md](docs/architecture.md)，API 格式、上下文预算与函数定义见 [docs/agent-runtime.md](docs/agent-runtime.md)。

## macOS 测试包

已生成包含 Apple Silicon 和 Intel 架构的 `Alice.app`，测试者无需开发环境。

[下载 macOS 测试包](https://github.com/sketcherrr/alice/actions/runs/44687261596/artifacts/14607007955)（需登录 GitHub，附件保留至 2026-12-04）。解压下载附件，再解压其中的 `Alice-macOS-universal-test.zip`，将 `Alice.app` 拖入“应用程序”。本地已取回同名应用压缩包，位于 `dist/`。

测试版使用临时签名，尚未通过 Apple 公证；首次打开被系统阻止时，可前往“系统设置 → 隐私与安全性”允许打开。构建脚本为 `scripts/build-macos.sh`，自动构建流程为 `.github/workflows/macos-test.yml`；后续相关代码提交会自动生成新测试包。

详情见 [macOS 测试版构建](docs/macos-testing.md)。

## 0.2 桌宠与小游戏

新功能与操作说明见 [桌宠与小游戏](docs/desktop-and-arcade.md)。Windows 原生窗口代码另有编译工作流；它仍不等于已完成 Rust/SQLite 运行库打包的 Windows 发行版。

## 0.3 音乐与语音

桌面操作条提供麦克风和音乐按钮；右键人物 →「声音小窝」选择曲目与音色。操作、数据流、系统依赖及接口说明见 [音乐与语音](docs/audio.md)。语音使用你自己的 OpenAI 额度；本轮测试使用模拟接口，实际中文音色与麦克风需要真机试听。

## 0.4 · 树莓派设备模式预览

Linux 电脑先预览：

```bash
./scripts/run-device.sh --preview
```

全屏运行：`./scripts/run-device.sh`。普通透明桌宠继续用 `./scripts/run-linux.sh`。设备模式也可通过 `ALICE_DEVICE_MODE=1` 或 `--device` 启动；预览通过 `ALICE_DEVICE_MODE=preview` 或 `--device-preview` 启动。当前原生全屏窗口仅在 Linux 接入。

- 触摸角色、聊天、照顾她、听歌；更多设置收在右上角抽屉。
- 「待机与欢迎」支持自定义欢迎语、三种主题、本地背景图、时钟和待机时间。待机停止角色动画，触摸唤醒；目前是应用画面变暗，尚未控制屏幕背光或整机休眠。
- 「照顾她」提供喂点心、洗泡泡澡和睡眠／唤醒。饱腹、清洁和睡眠存入 SQLite；休息按经过时间恢复精力，重复点击不会直接刷精力。喂食／洗澡使用现有角色帧搭配程序绘制的点心、泡泡动效，尚未新增专用人物图集。
- 「声音小窝」可导入普通 MP3／WAV／FLAC，复制到自己的音乐目录，单曲循环、调音量及 15／30／60 分钟定时暂停。每首最多 128 MB、最多 100 首；重复内容不会重复收藏；移除收藏不删除原始文件。目标系统须有相应解码器。暂不支持加密音乐文件、播放队列、随机播放和网易云独立登录。
- Linux 设备模式下的「连接 Wi-Fi」通过 NetworkManager D-Bus 扫描、保存和连接网络。2.4GHz／5GHz 同名网络分开显示；选中 5GHz 会保存 `band=a`，不会默默改成 2.4GHz。支持普通开放网络、WPA-PSK 和 SAE 配置；企业网络、隐藏网络请先通过系统设置配置。实际连接、WPA3 和重连行为待真机验证。
- 配网密码交给系统网络管理器保存，不写宠物存档、日志或 AI 上下文。必须使用有网络管理权限的图形登录用户，无需用 root 运行 Alice。无线国家／地区应在 Raspberry Pi Imager 或系统设置中设为实际所在地；5GHz 可用信道由网卡、驱动及地区规定决定。

树莓派 5 使用带图形桌面的 **64 位 Raspberry Pi OS**，先安装 Flutter、Rust，以及 GTK 3／SQLite／GStreamer 开发库、NetworkManager、PipeWire、录音所需的 `parecord`、`pactl`、`ffmpeg`。在 ARM64 构建机执行：

```bash
./scripts/build-raspberry-pi.sh
```

该脚本拒绝在 x64 上生成冒充 ARM64 的包，成功后输出 `dist/Alice-linux-arm64-test.tar.gz`。保留整个解压目录，通过 `ALICE_DEVICE_MODE=1 ./alice_companion` 启动。当前工作机只有 x64，没有已验证的树莓派安装包。

需要随图形桌面启动时，显式安装当前用户的启动项：

```bash
python3 scripts/install-device-autostart.py /完整路径/bundle
# 取消自启动，保留存档与音乐：
python3 scripts/install-device-autostart.py --remove
```

启动项会在异常退出后有限重试，正常退出不重启；系统桌面自动登录需要另外在树莓派系统设置中开启。请保留 bundle 位置不变。

**存档升级：** 新版事务性迁移到 schema 2，保留原有人设、记忆、聊天和进度；旧版程序会拒绝打开新版存档。测试新版前可复制整个 Alice 数据目录作为回退备份。设备外观在 `device.json`，导入音乐在 `music/`，与 `companion.sqlite3` 同目录。API Key 仍仅在进程内保留。

硬件到手后的验收：5GHz 连接、重启自动重连、断线恢复、麦克风／扬声器、触摸、长时间运行、正常关机和重启后的存档。iPhone BLE 同步、蓝牙音箱、物理摸头／震动感应、背光控制和网易云播放接入是后续阶段，本版未实现。设备界面离线检查入口为 `apps/companion/lib/smoke_device.dart`。
