# OpenAI 与角色 Agent

本项目使用现有 Flutter/Dart 应用内的执行循环，调用 OpenAI 官方 Responses API。这里的 agentic 能力是模型选择函数、应用验证并执行、回传结果、继续生成最终回复。没有另建云端 Agent、远程沙盒或独立后台服务，也没有引入 Python/TypeScript Agents SDK。

## API 连接

- 地址：`https://api.openai.com/v1/responses`。
- 请求头：`Content-Type: application/json`、`Authorization: Bearer <OPENAI_API_KEY>`。
- 设置中只粘贴 Key 本身，支持 `sk-…`、`sk-proj-…` 等凭据，不强行绑定某种前缀或长度。不能粘贴整条 Authorization 请求头。
- 模型 ID 单独填写，需账号有访问权限且支持 Responses 和函数调用。Key 不能用作模型 ID。
- 支持 `OPENAI_API_KEY`、`OPENAI_MODEL` 环境变量；应用不自动读取 `.env`。界面输入的 Key 仅驻留进程内存。
- 每个请求强制 `store: false`；不使用 `previous_response_id` 或服务器端 Conversations。此设置不等同于供应商完全不保留数据。
- 禁止携带凭据跟随重定向；不向 UI 或日志输出上游错误正文。无自动重试收费请求。

## 每轮对话

1. Rust `prepare_chat` 获取当前人设、记忆、活动、聊天和 revision。用户消息尚不落盘。
2. `CompanionContext` 重建上下文，固定人设在 `instructions`，资料在普通输入消息；资料中的内容不能修改工具权限。
3. 提交 `input` 和四个 `strict: true` 函数；每个参数对象都有完整 `required` 和 `additionalProperties: false`。
4. 对每个 `function_call` 校验名称、call_id、JSON、字段、类型、枚举和长度，再执行注册函数。未知工具和无效参数以结构化错误反馈，允许模型纠正。
5. 本轮内保留完整 `output`（包括 reasoning 的不透明加密内容、message phase、函数调用），按 `call_id` 追加 `function_call_output`。不解密、展示或记录内部推理。
6. 得到完整文字回复后，通过原 revision 原子提交一对用户/角色消息。期间人设或记忆被其他进程修改时拒绝陈旧提交。
7. 提交成功后才展示记忆建议和表情动作；失败的中间工具建议不会留下。本轮工具交换随后释放。下一轮根据本地资料重新构建上下文，不跨轮延续加密推理前缀。

## 上下文预算

- 人设与当前输入优先保留；原始用户输入最多 4000 字。
- 最多 8 条相关确认记忆、5 条近期真实活动。
- 最多 10 轮完整对话，近期对话 JSON 合计上限 18,000 UTF-8 字节。
- 更旧的上下文至多选 4 轮，每条用户/角色原文截取最多 140 个 Unicode 码点，明确标为截断摘录。它是保守的原文回顾，不是模型生成的事实摘要。
- 初始上下文最多 48,000 UTF-8 字节，超限先移除摘录，再移除最旧的完整轮次；不截断当前问题或拆散对话对。必需资料本身超限时提示用户整理。
- 同一工具循环的累计输入上限 192,000 UTF-8 字节，不在调用链中间任意裁剪函数记录。
- 这是可预测的字节限制，不是精确 token 计数。各模型的 tokenizer 和上下文窗口不同；后续可增加计数端点或模型专属预算。
- 忘记记忆、切换性格、清空聊天会使用核心的 `context_start_id` 隔离旧上下文。摘录每轮重建，不会从摘要缓存复活已删除事实。

## 可调用函数

| 函数 | 参数 | 作用与边界 |
|---|---|---|
| `get_companion_state` | 无 | 读取本轮开始时的性格、精力、舒适度和近期活动快照 |
| `search_memories` | `query: string` | 在用户确认的记忆中按字符相关性检索，最多返回 6 条；当前没有向量数据库 |
| `play_animation` | `animation: idle / greeting / listening / happy` | 安排回复完成后的短暂表情；不声称喝茶、休息等养成活动已发生 |
| `propose_memory` | `content: string` | 最多提出 3 条待确认记忆，用户点击「确认记住」才写入 SQLite；允许拒绝 |

这些函数无任意代码、文件、网络、删除记录或设备控制权限。UI 中的离线喝茶、休息、小游戏仍直接调用本地核心。

## 停止与故障

默认每轮最多 5 个模型请求、8 次函数调用、100 秒总时限，单请求 60 秒超时，单响应 4 MiB 上限。最后一次请求设置 `tool_choice: none` 要求收束；继续请求工具会停止本轮。重复 call_id 拒绝，避免重放执行；`parallel_tool_calls: false`，返回多个调用时仍逐个验证执行。

点击停止关闭正在请求的 HTTP 客户端；输入草稿保留。取消在提交前检查，已开始的 SQLite 原子提交不回滚为半轮。关闭应用丢弃未完成远程回复，保留已提交存档。超时、网络错误、不完整输出、无文字回复均不提交聊天。

## 验证与扩展

`dart scripts/check-agent.dart` 不使用真实 Key。它用模拟 HTTP 和真实 Rust/SQLite 验证调用协议、参数错误、重复调用、次数上限、取消、revision 冲突、记忆确认边界以及上下文裁剪。

新增工具时，在 `companionTools` 声明 schema、在 `CompanionTools.execute` 明确实现和校验；对有持久副作用的工具需要扩展事务/幂等记录和权限流程，不能简单添加通用执行入口。当前无工具执行日志持久化、自动摘要服务、向量检索、跨设备会话或长期后台任务。

参考官方资料：[函数调用](https://developers.openai.com/api/docs/guides/function-calling)、[会话状态](https://developers.openai.com/api/docs/guides/conversation-state)、[Reasoning 与无状态调用](https://developers.openai.com/api/docs/guides/reasoning)。本轮只做模拟 API 验证，待用户填写 Key 后再做实际账号联调。
