import 'package:flutter/material.dart';
import 'openai.dart';
import 'openai_network.dart';

class ConnectionSettings {
  final String key, model;
  final NetworkSettings network;
  const ConnectionSettings(this.key, this.model, this.network);
}

typedef ConnectionChecker =
    Future<String> Function(String, String, NetworkSettings, TurnCancellation);

class ConnectionDialog extends StatefulWidget {
  final String initialKey, initialModel;
  final NetworkSettings initialNetwork;
  final String? initialError;
  final ConnectionChecker? checker;
  const ConnectionDialog({
    super.key,
    required this.initialKey,
    required this.initialModel,
    this.initialNetwork = const NetworkSettings(),
    this.initialError,
    this.checker,
  });
  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  late final keyInput = TextEditingController(text: widget.initialKey);
  late final modelInput = TextEditingController(text: widget.initialModel);
  late final proxyInput = TextEditingController(
    text: widget.initialNetwork.proxy,
  );
  late ProxyMode mode = widget.initialNetwork.mode;
  late String? report = widget.initialError;
  bool checking = false, succeeded = false;
  TurnCancellation? cancellation;
  NetworkSettings get network =>
      NetworkSettings(mode: mode, proxy: proxyInput.text.trim());

  @override
  void dispose() {
    cancellation?.cancel();
    keyInput.dispose();
    modelInput.dispose();
    proxyInput.dispose();
    super.dispose();
  }

  void changed(String _) => setState(() {
    report = null;
    succeeded = false;
  });
  void validate({bool allowEmpty = false}) {
    if (!allowEmpty || keyInput.text.trim().isNotEmpty) {
      OpenAiChat.validateCredentials(keyInput.text, modelInput.text);
    }
    if (mode == ProxyMode.manual)
      OpenAiNetwork.manualDirective(proxyInput.text);
  }

  Future<void> check() async {
    try {
      validate();
    } catch (e) {
      setState(() {
        report = e.toString();
        succeeded = false;
      });
      return;
    }
    final token = TurnCancellation();
    cancellation = token;
    setState(() {
      checking = true;
      report = null;
      succeeded = false;
    });
    try {
      final key = keyInput.text.trim(), model = modelInput.text.trim();
      final result = widget.checker == null
          ? await OpenAiChat(
              network: network,
              timeout: const Duration(seconds: 20),
            ).checkConnection(key: key, model: model, cancellation: token)
          : await widget.checker!(key, model, network, token);
      if (mounted && !token.cancelled)
        setState(() {
          report = result;
          succeeded = true;
        });
    } catch (e) {
      if (mounted && !token.cancelled)
        setState(() {
          report = e is ChatFailure || e is NetworkFailure
              ? e.toString()
              : '检查未完成，请重试。';
          if (e is ChatFailure && e.statusCode == 403) {
            report = '$report\n本检查需要读取模型权限；该权限与发送聊天的权限可能不同。';
          }
        });
    } finally {
      if (mounted)
        setState(() {
          checking = false;
          cancellation = null;
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('连接 OpenAI'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('填入你自己的 Key，就能和 Alice 聊天、说话。'),
            const SizedBox(height: 20),
            TextField(
              key: const ValueKey('api-key'),
              controller: keyInput,
              obscureText: true,
              enabled: !checking,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: changed,
              decoration: const InputDecoration(
                labelText: 'OpenAI API Key',
                hintText: 'sk-… 或 sk-proj-…',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('api-model'),
              controller: modelInput,
              enabled: !checking,
              autocorrect: false,
              onChanged: changed,
              decoration: const InputDecoration(
                labelText: '聊天模型 ID',
                hintText: '填写你的账号可用的模型',
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<ProxyMode>(
              key: const ValueKey('api-network'),
              initialValue: mode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '连接方式'),
              items: const [
                DropdownMenuItem(
                  value: ProxyMode.automatic,
                  child: Text('自动（系统／环境代理）'),
                ),
                DropdownMenuItem(
                  value: ProxyMode.manual,
                  child: Text('手动 HTTP 代理'),
                ),
                DropdownMenuItem(value: ProxyMode.direct, child: Text('直接连接')),
              ],
              onChanged: checking
                  ? null
                  : (value) => setState(() {
                      mode = value!;
                      report = null;
                      succeeded = false;
                    }),
            ),
            if (mode == ProxyMode.manual) ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('api-proxy'),
                controller: proxyInput,
                enabled: !checking,
                autocorrect: false,
                onChanged: changed,
                decoration: const InputDecoration(
                  labelText: 'HTTP 代理地址',
                  hintText: 'http://127.0.0.1:7890',
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '端口请以代理软件的 HTTP／混合端口为准。',
                style: TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              '检查连接只读取模型信息，不发送对话、记忆或录音，也不生成回复。\nKey 和手动连接配置仅用于本次启动，不写入存档。聊天与语音共用连接方式。',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF8A8CA4),
                height: 1.7,
              ),
            ),
            if (checking)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (report != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SelectableText(
                  report!,
                  key: const ValueKey('connection-report'),
                  style: TextStyle(
                    color: succeeded
                        ? const Color(0xFF35725C)
                        : Colors.redAccent,
                    height: 1.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          cancellation?.cancel();
          Navigator.pop(context);
        },
        child: const Text('稍后再说'),
      ),
      TextButton(
        key: const ValueKey('check-connection'),
        onPressed: checking ? null : check,
        child: const Text('检查连接'),
      ),
      FilledButton.tonal(
        onPressed: checking
            ? null
            : () {
                try {
                  validate(allowEmpty: true);
                } catch (e) {
                  setState(() {
                    report = e.toString();
                    succeeded = false;
                  });
                  return;
                }
                Navigator.pop(
                  context,
                  ConnectionSettings(
                    keyInput.text.trim(),
                    modelInput.text.trim(),
                    network,
                  ),
                );
              },
        child: const Text('保存设置'),
      ),
    ],
  );
}
