// In-memory diagnostics/proxy checks: no sockets, real credentials or API calls.
import 'dart:io';
import 'dart:convert';
import '../apps/companion/lib/openai.dart';
import '../apps/companion/lib/openai_network.dart';
import 'check-offline.dart' show Client, check;

class ProxyClient extends Client {
  String Function(Uri)? route;
  ProxyClient() : super(200, '{}');
  @override
  set findProxy(String Function(Uri)? value) => route = value;
}

class ProbeClient extends Client {
  int gets = 0;
  ProbeClient(super.status, super.body);
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    gets++;
    called = uri;
    return request;
  }
}

Future<void> main() async {
  final target = Uri.parse('https://api.openai.com/v1/responses');
  for (final input in [
    'http://127.0.0.1:7890',
    'http://localhost:8080/',
    'http://[::1]:7890',
  ]) {
    check(
      OpenAiNetwork.manualDirective(input).startsWith('PROXY '),
      'HTTP proxy accepted',
    );
  }
  for (final input in [
    '',
    'socks5://localhost:7890',
    'https://localhost:7890',
    'http://user:password@localhost:7890',
    'http://localhost',
    'http://localhost:7890/path',
    'http://localhost:7890?key=secret',
    'http://localhost:0',
  ]) {
    try {
      OpenAiNetwork.manualDirective(input);
      throw StateError('invalid proxy accepted');
    } on NetworkFailure catch (e) {
      check(!e.message.contains('secret'), 'invalid proxy values not echoed');
    }
  }
  final client = ProxyClient();
  var lookups = 0;
  Future<Map<String, dynamic>> system(Uri uri) async {
    check(uri == target, 'resolve actual destination');
    lookups++;
    return {'kind': 'http', 'host': '127.0.0.1', 'port': 7890};
  }

  final description = await OpenAiNetwork.configure(
    client,
    target,
    environment: {},
    resolver: system,
  );
  check(
    description.contains('系统代理') &&
        lookups == 1 &&
        client.route!(target) == 'PROXY 127.0.0.1:7890',
    'Finder launch uses system proxy',
  );
  await OpenAiNetwork.configure(
    client,
    target,
    environment: {'https_proxy': 'localhost:8080'},
    resolver: system,
  );
  check(
    lookups == 1 && client.route!(target) == 'PROXY localhost:8080',
    'terminal environment precedence',
  );
  await OpenAiNetwork.configure(
    client,
    target,
    environment: {
      'https_proxy': 'localhost:8080',
      'no_proxy': 'api.openai.com',
    },
    resolver: system,
  );
  check(
    lookups == 1 && client.route!(target) == 'DIRECT',
    'NO_PROXY is not overridden by the system proxy',
  );
  await OpenAiNetwork.configure(
    client,
    target,
    configuration: const NetworkSettings(mode: ProxyMode.direct),
    resolver: system,
  );
  check(
    lookups == 1 && client.route!(target) == 'DIRECT',
    'explicit direct overrides proxy',
  );
  await OpenAiNetwork.configure(
    client,
    target,
    configuration: const NetworkSettings(
      mode: ProxyMode.manual,
      proxy: 'http://localhost:9090',
    ),
    resolver: system,
  );
  check(
    lookups == 1 && client.route!(target) == 'PROXY localhost:9090',
    'explicit manual override',
  );
  for (final kind in ['pac', 'socks', 'unknown']) {
    final blocked = ProxyClient();
    try {
      await OpenAiNetwork.configure(
        blocked,
        target,
        environment: {},
        resolver: (_) async => {'kind': kind},
      );
      throw StateError('unsupported system proxy silently bypassed');
    } on NetworkFailure {}
    check(blocked.route == null, 'no silent direct fallback');
  }
  print(
    'PASS: system proxy, environment precedence, manual/direct modes, invalid URL rejection and no unsupported-proxy bypass.',
  );

  for (final entry in {
    'insufficient_quota': '额度不足',
    'rate_limit_exceeded': '速率限制',
    'model_not_found': '无法访问',
    'invalid_api_key': '未接受',
  }.entries) {
    final c = Client(
      entry.key == 'model_not_found'
          ? 404
          : entry.key == 'invalid_api_key'
          ? 401
          : 429,
      jsonEncode({
        'error': {
          'code': entry.key,
          'message': 'NEVER_SHOW secret-key private-dialogue',
        },
      }),
    );
    try {
      await OpenAiChat(
        clientFactory: () => c,
      ).send(key: 'secret-key', model: 'gpt-6-astra', request: {});
      throw StateError('error accepted');
    } on ChatFailure catch (e) {
      check(
        e.message.contains(entry.value) &&
            e.message.contains(entry.key) &&
            e.message.contains('HTTP '),
        'specific failure diagnostic',
      );
      check(
        !e.message.contains('secret-key') &&
            !e.message.contains('private-dialogue'),
        'upstream message remains private',
      );
    }
  }
  final probe = ProbeClient(200, '{"id":"gpt-6-astra","object":"model"}');
  final result = await OpenAiChat(
    clientFactory: () => probe,
  ).checkConnection(key: 'test-only', model: 'gpt-6-astra');
  check(
    probe.gets == 1 &&
        probe.called.toString() ==
            'https://api.openai.com/v1/models/gpt-6-astra',
    'model metadata GET',
  );
  check(
    probe.request.bytes.isEmpty &&
        !probe.request.followRedirects &&
        probe.closed,
    'no chat/body, no redirects, close probe',
  );
  check(
    result.contains('未生成回复'),
    'probe does not claim paid generation verified',
  );
  final incomplete = Client(
    200,
    '{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}',
  );
  try {
    await OpenAiChat(
      clientFactory: () => incomplete,
    ).send(key: 'test-only', model: 'gpt-6-astra', request: {});
    throw StateError('incomplete accepted');
  } on ChatFailure catch (e) {
    check(
      e.message.contains('输出上限'),
      'reasoning truncation distinguished from network',
    );
  }
  print(
    'PASS: API quota/rate/model/auth distinctions, redaction, GET-only connection check and incomplete reasoning diagnosis.',
  );
}
