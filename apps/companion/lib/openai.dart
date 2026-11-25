import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'api_failure.dart';
import 'openai_network.dart';

class ChatFailure implements Exception {
  final String message;
  final int? statusCode;
  ChatFailure(this.message, {this.statusCode});
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
  final bool _configureNetwork;
  final NetworkSettings? network;
  OpenAiChat({
    Uri? endpoint,
    this.timeout = const Duration(seconds: 60),
    HttpClient Function()? clientFactory,
    this.network,
  }) : clientFactory = clientFactory ?? HttpClient.new,
       _configureNetwork = clientFactory == null,
       endpoint = endpoint ?? Uri.parse('https://api.openai.com/v1/responses');

  static void validateCredentials(String key, String model) {
    if (key.trim().isEmpty) throw ChatFailure('请在连接设置中填写 OpenAI API Key。');
    if (key.trim().contains(RegExp(r'\s')) ||
        key.trim().toLowerCase().startsWith('bearer')) {
      throw ChatFailure('只需粘贴 API Key 本身，不要添加 Bearer、空格或换行。');
    }
    if (model.trim().isEmpty) throw ChatFailure('请填写你的 OpenAI 账号可用的模型 ID。');
    if (model.trim().startsWith('sk-') ||
        !RegExp(r'^[A-Za-z0-9._:-]{1,200}$').hasMatch(model.trim())) {
      throw ChatFailure('模型 ID 格式不正确；模型一栏不要填写 Key 或网址。');
    }
  }

  /// Read model metadata only: no chat, memory, audio or generation request.
  Future<String> checkConnection({
    required String key,
    required String model,
    TurnCancellation? cancellation,
  }) async {
    validateCredentials(key, model);
    final target = endpoint.resolve(
      'models/${Uri.encodeComponent(model.trim())}',
    );
    var route = '';
    final body = await _request(
      target,
      key,
      cancellation,
      method: 'GET',
      onRoute: (value) => route = value,
    );
    if (body['id'] != model.trim()) throw ChatFailure('模型检查返回了无法识别的数据。');
    return '已连接 OpenAI，并可读取该模型。${route.isEmpty ? '' : '\n连接方式：$route'}'
        '\n本次未生成回复；聊天权限与额度仍以实际聊天结果为准。';
  }

  Future<Map<String, dynamic>> respond({
    required String key,
    required String model,
    required Map<String, dynamic> request,
    TurnCancellation? cancellation,
  }) async {
    validateCredentials(key, model);
    final body = await _request(
      endpoint,
      key,
      cancellation,
      payload: {...request, 'model': model.trim(), 'store': false},
    );
    if (body['status'] != 'completed') {
      final reason = body['incomplete_details'] is Map
          ? body['incomplete_details']['reason']
          : null;
      if (reason == 'max_output_tokens')
        throw ChatFailure('模型已连接，但本轮推理或回复达到输出上限，未生成完整回答；输入已保留。');
      throw ChatFailure('模型已连接，但回复未完整生成；输入已保留。');
    }
    if (body['output'] is! List) throw ChatFailure('服务没有返回有效的回复。');
    return body;
  }

  Future<Map<String, dynamic>> _request(
    Uri target,
    String key,
    TurnCancellation? cancellation, {
    String method = 'POST',
    Map<String, dynamic>? payload,
    void Function(String)? onRoute,
  }) async {
    if (target.scheme != 'https' &&
        !['127.0.0.1', '::1', 'localhost'].contains(target.host)) {
      throw ChatFailure('对话服务需要安全的 HTTPS 连接。');
    }
    cancellation?.check();
    final client = clientFactory()..connectionTimeout = timeout;
    void abort() => client.close(force: true);
    cancellation?.add(abort);
    try {
      return await (() async {
        if (_configureNetwork) {
          final route = await OpenAiNetwork.configure(
            client,
            target,
            configuration: network,
          );
          onRoute?.call(route);
        }
        cancellation?.check();
        final req = method == 'GET'
            ? await client.getUrl(target)
            : await client.postUrl(target);
        cancellation?.check();
        req.followRedirects = false;
        req.headers.contentType = ContentType.json;
        req.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${key.trim()}',
        );
        if (payload != null) req.add(utf8.encode(jsonEncode(payload)));
        final response = await req.close();
        if (response.statusCode != 200) {
          throw ChatFailure(
            await apiFailure(response, key.trim()),
            statusCode: response.statusCode,
          );
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
        return body;
      })().timeout(timeout);
    } on ChatFailure {
      rethrow;
    } on NetworkFailure catch (e) {
      cancellation?.check();
      throw ChatFailure(e.message);
    } on TimeoutException {
      cancellation?.check();
      throw ChatFailure(
        '请求超时，输入已保留。请检查系统代理／HTTP 代理端口；若连接检查通过，也可能是模型本轮思考较久。\n网络诊断：timeout',
      );
    } on HandshakeException {
      cancellation?.check();
      throw ChatFailure('TLS 安全连接未建立，请检查代理与系统证书。未关闭证书校验。\n网络诊断：tls_handshake');
    } on SocketException {
      cancellation?.check();
      throw ChatFailure(
        '无法建立网络连接，请检查代理是否运行、HTTP 端口和 DNS；这不等于 Key 无效。\n网络诊断：socket_connection',
      );
    } on HttpException {
      cancellation?.check();
      throw ChatFailure('HTTP 连接中断或代理隧道未建立，请检查代理端口与连接方式。\n网络诊断：http_transport');
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
