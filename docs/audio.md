# 0.3 · 小岛电台与 Alice 的声音

桌面操作条增加麦克风与音乐按钮；右键人物 →「声音小窝」可以换曲、调音量、选择音色和试听。手机布局的麦克风位于聊天输入框旁，播放器在同一个抽屉中。桌面闲置时依然只显示角色。

## Lo-fi

内置《窗边小潮汐》（76 BPM）与《月亮寄来的明信片》（68 BPM），点击音乐按钮播放或暂停，单曲循环。完全离线，不需要 Key，启动时不会自动播放。曲目、音量、音色与自动朗读偏好保存到存档目录中的 `audio.json`。

两首音乐用振荡器和固定种子的噪声合成，包含电钢琴和弦、低音、轻鼓点、旋律与底噪。没有使用外部录音素材。制作脚本为 [compose-lofi.py](../scripts/compose-lofi.py)，音频、曲目信息和 CC0 声明在 [assets/audio](../assets/audio/)。运行应用无需 Python、NumPy 或 FFmpeg；Linux 录音所需的系统依赖另见下文。

## 按住说话

1. 在「连接 OpenAI」填写自己的 Key 与可用的聊天模型 ID。
2. 按住麦克风说话，松开发送。首次授权麦克风后，如录音未开始，再按住一次。
3. 录音识别成文字，继续走现有 Agent 的上下文、函数调用和记忆确认流程，然后播放角色语音。

移出麦克风按钮、系统取消触摸或切换应用会取消录音。录音最长 60 秒，达到上限会丢弃这一段；不足 350ms 的误触不上传。输入框有未发送草稿时不会启动录音，避免覆盖草稿。识别成功但聊天失败时，识别文字留在输入框中；语音生成失败不撤回已经保存的文字回复。

仅在按住期间使用麦克风，松开后才上传 WAV 到 OpenAI。临时录音在读取或取消后删除，生成的语音在播放或停止后删除；没有录音历史或音频云同步功能。异常退出时系统临时目录可能仍有未清理文件。Key 沿用原有的仅进程内保存方式。

## 角色声音

提供「轻甜」「元气」「轻声」三档，使用 `coral`、`shimmer`、`marin`，并加入可爱卡通女生的语气指令。音量独立于音乐，可联网试听、开启/关闭自动朗读，或随时按停止按钮中断生成与播放。声音为 AI 合成，实际声线需要使用自己的 Key 试听选择；本轮没有调用真实账户进行听感校准。

音乐在准备/播放角色语音时降低到用户音量的 22%，录音时静音，完成或取消后恢复。长于 1200 字的回复保留文字并提示不自动朗读。当前会等这一段音频完整生成后播放。

## 接口与上下文

根据 2026-11-19 查询的官方文档：

- 录音通过 `POST https://api.openai.com/v1/audio/transcriptions` 发送 multipart WAV，使用 `gpt-transcribe`。[文件转写文档](https://developers.openai.com/api/docs/guides/speech-to-text)
- 声音通过 `wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1-mini` 生成，输出 24kHz、单声道、16 位 PCM，再封装为 WAV。[Realtime 文档](https://developers.openai.com/api/docs/guides/realtime-conversations)
- 语音请求使用 `conversation: none`，只携带待朗读文本、声音方向和空工具列表，完成后关闭连接。聊天及记忆继续由现有 Responses Agent 管理。
- 官方已公布旧 Speech 模型的停用计划，本次新增功能采用当前 Realtime 模型。[语音生成文档](https://developers.openai.com/api/docs/guides/text-to-speech)

所有语音请求都带 Bearer Key，禁止 HTTP 重定向，限制时长和响应大小，取消时关闭连接；不自动重试收费请求，不显示可能包含凭据或用户内容的上游错误原文。录音识别、文字思考和声音生成是分开的 API 调用，会分别使用账户额度。

## 平台与验证

播放使用 `audioplayers 6.8.1`，录音使用 `record 7.2.0`。macOS/iOS 已增加麦克风用途描述，macOS Sandbox 已启用 `audio-input`，Android 已加入录音和联网权限。音频插件支持原有目标平台；移动端与树莓派整体应用仍需原生核心分发与真机验证。

Linux 播放需要 GStreamer（开发构建还需要 `gstreamer-1.0`、`gstreamer-app-1.0`、`gstreamer-audio-1.0` 的开发文件）；录音插件需要 `parecord`、`pactl` 和 `ffmpeg`。系统还需要可用的声音服务和输入/输出设备。[录音插件说明](https://pub.dev/packages/record)

离线协议检查：

```bash
dart --packages=apps/companion/.dart_tool/package_config.json scripts/check-voice.dart
```

Flutter 测试覆盖按住/松开/移出、权限拒绝、授权未完成就松开、停止后迟到的语音、音量压低与恢复、偏好保存和完整的模拟语音聊天链路。网络、模型和设备均可注入模拟实现，检查不需要真实 Key。`lib/smoke_desktop.dart` 另包含声音面板的实际渲染截图。
