# Alice · 小小鲸屿

一个本地优先的角色伙伴原型：以单一角色为中心的简洁陪伴窗口，三种可选性格、离线互动、长期记忆与 OpenAI Agent 文字对话。

**[去小小鲸屿坐坐 →](https://sketcherrr.github.io/alice/)** · 项目介绍、角色互动预览与下载入口。网页源码位于 [website/](website/README.md)，由 GitHub Pages 自动发布。

当前完成 Linux 桌面原型，并已在 macOS CI 构建出 Apple Silicon + Intel 通用测试应用；静态分析、13 项 Flutter 测试及实际 Rust/SQLite 检查通过。Mac 桌面人工体验仍待测试。Windows、Android、iOS 已有 Flutter 平台工程，原生库打包、移动端数据目录及真机验证尚未完成；不能把这些工程视为已发布的平台版本。

## 现在可以做什么

- 首次选择「温柔但有主见」「聪明、略带俏皮」「慢热、细腻而克制」。
- 展示生图生成的鲸鱼主题角色，包含待机眨眼、挥手、倾听、思考、开心、喝茶、睡眠、伸懒腰 8 组动作（共 56 帧），带呼吸、动作淡入衔接及互动小特效。
- 喝茶、安静陪伴、休息、找珍珠、俄罗斯方块、打砖块；完全离线可用，新小游戏最佳成绩保存在本机。
- 小岛电台：两首内置原创 lo-fi，离线循环播放、切歌和音量调节。
- 按住说话、松开发送，识别后接入原有聊天与记忆流程；AI 合成的卡通女生声音有轻甜、元气、轻声三档，支持试听与自动朗读。录音时静音音乐，说话时降低音乐音量。
- SQLite 自动保存性格、状态、活动和聊天；重新打开恢复。
- 在抽屉面板添加、查看和删除长期记忆；模型可提出记忆建议，经你确认才保存。切换性格保留记忆、聊天和养成进度。
- 配置 OpenAI API Key 与账号可用的模型 ID 后，使用 Responses API 进行文字聊天，支持记忆检索、状态读取、表情安排和待确认记忆的函数调用循环。
- 没有 Key、断网、超时或 API 返回错误时，保留输入，小屋继续可用。

本轮不包含摄像头、屏幕理解、无需确认的自动记忆保存、云同步和正式发行签名/公证。这些是后续阶段，不显示成已经可用的按钮。

## 在 Linux 上启动

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

[下载 macOS 测试包](https://github.com/sketcherrr/alice/actions/runs/44455053204/artifacts/14497940287)（需登录 GitHub，附件保留至 2026-12-03）。解压下载附件，再解压其中的 `Alice-macOS-universal-test.zip`，将 `Alice.app` 拖入“应用程序”。本地已取回同名应用压缩包，位于 `dist/`。

测试版使用临时签名，尚未通过 Apple 公证；首次打开被系统阻止时，可前往“系统设置 → 隐私与安全性”允许打开。构建脚本为 `scripts/build-macos.sh`，自动构建流程为 `.github/workflows/macos-test.yml`；后续相关代码提交会自动生成新测试包。

详情见 [macOS 测试版构建](docs/macos-testing.md)。

## 0.2 桌宠与小游戏

新功能与操作说明见 [桌宠与小游戏](docs/desktop-and-arcade.md)。Windows 原生窗口代码另有编译工作流；它仍不等于已完成 Rust/SQLite 运行库打包的 Windows 发行版。

## 0.3 音乐与语音

桌面操作条提供麦克风和音乐按钮；右键人物 →「声音小窝」选择曲目与音色。操作、数据流、系统依赖及接口说明见 [音乐与语音](docs/audio.md)。语音使用你自己的 OpenAI 额度；本轮测试使用模拟接口，实际中文音色与麦克风需要真机试听。
