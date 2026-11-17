import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:alice_companion/openai.dart';

void main() {
  test(
    'Responses request uses bearer auth, store=false, and parses typed assistant items',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final handled = server.first.then((req) async {
        expect(req.uri.path, '/v1/responses');
        expect(req.headers.value('authorization'), 'Bearer test-only');
        final body = jsonDecode(await utf8.decoder.bind(req).join());
        expect(body['store'], false);
        expect(body['model'], 'test-model');
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({
            'status': 'completed',
            'output': [
              {'type': 'reasoning', 'summary': []},
              {
                'type': 'message',
                'role': 'assistant',
                'content': [
                  {'type': 'output_text', 'text': '你好，今天也一起坐坐。'},
                ],
              },
            ],
          }),
        );
        await req.response.close();
      });
      final chat = OpenAiChat(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/responses'),
      );
      expect(
        await chat.send(
          key: 'test-only',
          model: 'test-model',
          request: {'input': '你好', 'store': true},
        ),
        '你好，今天也一起坐坐。',
      );
      await handled;
    },
  );
  test('upstream error bodies cannot expose secrets to the UI', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final handled = server.first.then((req) async {
      await req.drain<void>();
      req.response.statusCode = 401;
      req.response.write('secret-server-detail');
      await req.response.close();
    });
    final chat = OpenAiChat(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/v1/responses'),
    );
    await expectLater(
      chat.send(key: 'test-only', model: 'test-model', request: {}),
      throwsA(
        isA<ChatFailure>().having(
          (e) => e.message,
          'message',
          allOf(contains('Key'), isNot(contains('secret-server-detail'))),
        ),
      ),
    );
    await handled;
  });
  test('missing credentials fail before making a network request', () async {
    await expectLater(
      OpenAiChat().send(key: '', model: '', request: {}),
      throwsA(isA<ChatFailure>()),
    );
  });
  test('incomplete responses are not saved as completed dialogue', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final handled = server.first.then((req) async {
      await req.drain<void>();
      req.response.write('{"status":"incomplete","output":[]}');
      await req.response.close();
    });
    await expectLater(
      OpenAiChat(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      ).send(key: 'test-only', model: 'test-model', request: {}),
      throwsA(isA<ChatFailure>()),
    );
    await handled;
  });
}
