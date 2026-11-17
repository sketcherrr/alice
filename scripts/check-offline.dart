// Standalone tests for restricted environments: no listening socket or API key.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../apps/companion/lib/openai.dart';
import '../apps/companion/lib/core.dart';

void check(bool value, String message) {
  if (!value) {
    throw StateError(message);
  }
}

class Headers implements HttpHeaders {
  final values = <String, String>{};
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value.toString();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Response extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;
  Response(this.statusCode, this.body);
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Request implements HttpClientRequest {
  @override
  final Headers headers = Headers();
  @override
  bool followRedirects = true;
  final bytes = <int>[];
  final Response response;
  Request(this.response);
  @override
  void add(List<int> data) => bytes.addAll(data);
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Client implements HttpClient {
  @override
  Duration? connectionTimeout;
  final Request request;
  Uri? called;
  bool closed = false;
  Client(int status, String body) : request = Request(Response(status, body));
  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    called = url;
    return request;
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> main() async {
  final success = Client(
    200,
    jsonEncode({
      'status': 'completed',
      'output': [
        {'type': 'reasoning', 'summary': []},
        {
          'type': 'message',
          'role': 'assistant',
          'content': [
            {'type': 'output_text', 'text': '你好，小屋见。'},
          ],
        },
      ],
    }),
  );
  final text = await OpenAiChat(clientFactory: () => success).send(
    key: 'test-only',
    model: 'test-model',
    request: {'input': '你好', 'store': true},
  );
  check(text == '你好，小屋见。', 'typed output parse');
  check(
    success.called.toString() == 'https://api.openai.com/v1/responses',
    'official endpoint',
  );
  check(
    success.request.headers.values['authorization'] == 'Bearer test-only',
    'authorization',
  );
  check(
    !success.request.followRedirects,
    'credentials must not follow redirects',
  );
  final body = jsonDecode(utf8.decode(success.request.bytes));
  check(
    body['store'] == false && body['model'] == 'test-model',
    'request configuration',
  );
  check(success.closed, 'client cleanup');
  for (final status in [401, 403, 429, 500, 302]) {
    final client = Client(status, 'never-show-this-server-body');
    try {
      await OpenAiChat(
        clientFactory: () => client,
      ).send(key: 'test-only', model: 'test-model', request: {});
      throw StateError('expected failure');
    } on ChatFailure catch (e) {
      check(!e.message.contains('never-show'), 'redacted service failure');
    }
    check(client.closed, 'cleanup on failure');
  }
  final incomplete = Client(200, '{"status":"incomplete","output":[]}');
  try {
    await OpenAiChat(
      clientFactory: () => incomplete,
    ).send(key: 'test-only', model: 'test-model', request: {});
    throw StateError('incomplete accepted');
  } on ChatFailure {}
  final unused = Client(200, '');
  try {
    await OpenAiChat(
      clientFactory: () => unused,
    ).send(key: '', model: 'test-model', request: {});
    throw StateError('missing key accepted');
  } on ChatFailure {}
  check(unused.called == null, 'no network without key');
  print(
    'PASS: Responses request, parsing, status errors, redaction, redirect protection, missing key.',
  );

  final root = await Directory.systemTemp.createTemp('alice-offline-check-');
  try {
    final lib =
        Platform.environment['ALICE_CORE_LIBRARY'] ??
        File('target/release/libalice_core.so').absolute.path;
    final core = NativeCore('${root.path}/companion.sqlite3', lib);
    await core.call({'op': 'select_persona', 'id': 'clever_playful'});
    await core.call({'op': 'remember', 'content': '喜欢海边，也希望被认真倾听。'});
    await core.call({'op': 'action', 'action': 'tea'});
    final before = await core.call({'op': 'snapshot'});
    await core.call({'op': 'select_persona', 'id': 'reserved_attentive'});
    final reopened = await NativeCore(
      '${root.path}/companion.sqlite3',
      lib,
    ).call({'op': 'snapshot'});
    check(
      reopened['state']['persona'] == 'reserved_attentive',
      'persona switch',
    );
    check(
      reopened['state']['memories'][0]['content'] == '喜欢海边，也希望被认真倾听。',
      'UTF-8 durable memory',
    );
    check(
      jsonEncode(before['state']['messages']) ==
          jsonEncode(reopened['state']['messages']),
      'history preserved',
    );
    print(
      'PASS: Dart isolate → Rust FFI → SQLite, Unicode persistence, personality switch.',
    );
  } finally {
    await root.delete(recursive: true);
  }
}
