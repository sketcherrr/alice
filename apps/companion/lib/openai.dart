import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ChatFailure implements Exception {
  final String message;
  ChatFailure(this.message);
  @override
  String toString() => message;
}

/// Cancellation closes an in-flight socket; it never retries a paid request.
class TurnCancellation {
  bool cancelled = false;
  final Set<void Function()> _listeners = {};
  void check() {
    if (cancelled) throw ChatFailure('已停止回复，输入已保留。');
  }

  void add(void Function() fn) {
    if (cancelled) {
      fn();
    } else {
      _listeners.add(fn);
    }
  }

  void remove(void Function() fn) => _listeners.remove(fn);
  void cancel() {
    cancelled = true;
    for (final fn in _listeners.toList()) {
      fn();
    }
    _listeners.clear();
  }
}

/// Official Responses API. The key is an opaque credential, not a model ID.
class OpenAiChat {
  final Uri endpoint;
  final Duration timeout;
  final HttpClient Function() clientFactory;
  OpenAiChat({
    Uri? endpoint,
    this.timeout = const Duration(seconds: 60),
    HttpClient Function()? clientFactory,
  }) : clientFactory = clientFactory ?? HttpClient.new,
       endpoint = endpoint ?? Uri.parse('https://api.openai.com/v1/responses');

  Future<Map<String, dynamic>> respond({
    required String key,
    required String model,
    required Map<String, dynamic> request,
    TurnCancellation? cancellation,
  }) async {
    if (key.trim().isEmpty) throw ChatFailure('请在连接设置中填写 OpenAI API Key。');
    if (key.contains(RegExp(r'\s')) || key.toLowerCase().startsWith('bearer')) {
      throw ChatFailure('只需粘贴 API Key 本身，不要添加 Bearer、空格或换行。');
    }
    if (model.trim().isEmpty) throw ChatFailure('请填写你的 OpenAI 账号可用的模型 ID。');
    if (endpoint.scheme != 'https' &&
        !['127.0.0.1', '::1', 'localhost'].contains(endpoint.host)) {
      throw ChatFailure('对话服务需要安全的 HTTPS 连接。');
    }
    cancellation?.check();
    final client = clientFactory()..connectionTimeout = timeout;
    void abort() => client.close(force: true);
    cancellation?.add(abort);
    try {
      return await (() async {
        final req = await client.postUrl(endpoint);
        cancellation?.check();
        req.followRedirects = false;
        req.headers.contentType = ContentType.json;
        req.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${key.trim()}',
        );
        req.add(
          utf8.encode(
            jsonEncode({...request, 'model': model.trim(), 'store': false}),
          ),
        );
        final response = await req.close();
        if (response.statusCode != 200) {
          throw ChatFailure(switch (response.statusCode) {
            401 || 403 => 'Key 无效或没有访问权限，请检查 OpenAI Key 和模型权限。',
            429 => '请求过于频繁或额度不足，请稍后重试并检查账户额度。',
            >= 500 => '对话服务暂时不可用，本地陪伴仍然可以使用。',
            _ => '对话请求未成功（${response.statusCode}），请检查模型是否支持 Responses 与函数调用。',
          });
        }
        final buffer = <int>[];
        await for (final chunk in response) {
          cancellation?.check();
          buffer.addAll(chunk);
          if (buffer.length > 4 * 1024 * 1024)
            throw ChatFailure('回复过大，请缩短问题后重试。');
        }
        final body = jsonDecode(utf8.decode(buffer)) as Map<String, dynamic>;
        cancellation?.check();
        if (body['status'] != 'completed')
          throw ChatFailure('回复未完整生成，请重试或缩短问题。');
        if (body['output'] is! List) throw ChatFailure('服务没有返回有效的回复。');
        return body;
      })().timeout(timeout);
    } on ChatFailure {
      rethrow;
    } on TimeoutException {
      throw ChatFailure('连接超时，输入已保留。');
    } on SocketException {
      cancellation?.check();
      throw ChatFailure('暂时无法联网，输入已保留，本地互动仍可使用。');
    } catch (_) {
      cancellation?.check();
      throw ChatFailure('暂时无法读取回复，输入已保留，请稍后重试。');
    } finally {
      cancellation?.remove(abort);
      client.close(force: true);
    }
  }

  static String outputText(Map<String, dynamic> body) {
    final texts = <String>[];
    for (final item in body['output'] as List? ?? []) {
      if (item is! Map ||
          item['type'] != 'message' ||
          item['role'] != 'assistant')
        continue;
      for (final part in item['content'] as List? ?? []) {
        if (part is Map &&
            part['type'] == 'output_text' &&
            part['text'] is String)
          texts.add(part['text']);
        if (part is Map &&
            part['type'] == 'refusal' &&
            part['refusal'] is String)
          texts.add(part['refusal']);
      }
    }
    return texts.join('\n').trim();
  }

  Future<String> send({
    required String key,
    required String model,
    required Map<String, dynamic> request,
  }) async {
    final text = outputText(
      await respond(key: key, model: model, request: request),
    );
    if (text.isEmpty) throw ChatFailure('这次没有收到文字回复，请重试。');
    return text;
  }
}
