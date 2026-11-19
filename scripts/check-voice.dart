// Offline protocol regression checks. Never opens a network connection.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../apps/companion/lib/openai.dart';
import '../apps/companion/lib/voice_api.dart';
import 'check-offline.dart' show Client, check;

class ScriptedVoiceSocket implements VoiceSocket {
  final stream = StreamController<dynamic>();
  final sent = <Map<String, dynamic>>[];
  final String mode;
  bool closed = false;
  ScriptedVoiceSocket([this.mode = 'success']) {
    emit({'type': 'session.created'});
  }
  void emit(Map<String, dynamic> e) => stream.add(jsonEncode(e));
  @override
  Stream<dynamic> get events => stream.stream;
  @override
  void send(Map<String, dynamic> event) {
    sent.add(event);
    if (event['type'] == 'session.update') emit({'type': 'session.updated'});
    if (event['type'] == 'response.create') {
      if (mode == 'stall') return;
      if (mode == 'error') {
        emit({
          'type': 'error',
          'error': {'message': 'never-show-secret-key'},
        });
        return;
      }
      emit({
        'type': 'response.output_audio.delta',
        'delta': base64Encode([1, 0, 2, 0, 3, 0]),
      });
      if (mode == 'disconnect') {
        close();
        return;
      }
      emit({
        'type': 'response.done',
        'response': {
          'status': mode == 'incomplete' ? 'incomplete' : 'completed',
        },
      });
    }
  }

  @override
  void close() {
    if (!closed) {
      closed = true;
      unawaited(stream.close());
    }
  }
}

Future<void> runVoiceChecks() async {
  final pcm = Uint8List.fromList(List.generate(4800, (i) => i % 256));
  final wav = OpenAiVoice.pcmToWav(pcm);
  check(ascii.decode(wav.sublist(0, 4)) == 'RIFF', 'WAV header');
  check(
    ByteData.sublistView(wav).getUint32(24, Endian.little) == 24000,
    '24 kHz PCM',
  );
  check(wav.length == pcm.length + 44, 'bounded WAV payload');
  final client = Client(200, '{"text":"今天一起听音乐吧"}');
  final text = await OpenAiVoice(
    clientFactory: () => client,
  ).transcribe(wav, key: 'test-only', cancellation: TurnCancellation());
  check(text == '今天一起听音乐吧', 'transcript');
  check(
    client.called.toString() ==
        'https://api.openai.com/v1/audio/transcriptions',
    'official transcription URL',
  );
  check(
    client.request.headers.values['authorization'] == 'Bearer test-only',
    'bearer key',
  );
  check(
    !client.request.followRedirects && client.closed,
    'redirect protection and cleanup',
  );
  final body = latin1.decode(client.request.bytes);
  check(
    body.contains('gpt-transcribe') &&
        body.contains('filename="speech.wav"') &&
        body.contains(latin1.decode(wav)),
    'multipart file and model',
  );
  for (final status in [401, 403, 429, 500, 302]) {
    try {
      await OpenAiVoice(
        clientFactory: () => Client(status, 'never-show-secret-key'),
      ).transcribe(wav, key: 'test-only', cancellation: TurnCancellation());
      throw StateError('Expected status failure');
    } on VoiceFailure catch (e) {
      check(!e.message.contains('never-show'), 'redacted transcription errors');
    }
  }
  for (final response in ['{}', '{"text":""}', 'not-json']) {
    try {
      await OpenAiVoice(
        clientFactory: () => Client(200, response),
      ).transcribe(wav, key: 'test-only', cancellation: TurnCancellation());
      throw StateError('Invalid transcript accepted');
    } on VoiceFailure {}
  }
  var connections = 0;
  for (final key in ['', 'Bearer test-only']) {
    try {
      await OpenAiVoice(
        connector: (uri, key, token) async {
          connections++;
          return ScriptedVoiceSocket();
        },
      ).speak(
        '你好',
        key: key,
        style: VoiceStyle.sweet,
        cancellation: TurnCancellation(),
      );
      throw StateError('Invalid key accepted');
    } on VoiceFailure {}
  }
  check(connections == 0, 'no request with missing or malformed key');
  final socket = ScriptedVoiceSocket();
  final voice = OpenAiVoice(
    connector: (uri, key, token) async {
      check(
        uri.toString() ==
            'wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1-mini',
        'current Realtime endpoint',
      );
      check(key == 'test-only', 'voice key');
      return socket;
    },
  );
  final result = await voice.speak(
    '今天一起听音乐吧',
    key: 'test-only',
    style: VoiceStyle.sweet,
    cancellation: TurnCancellation(),
  );
  check(
    result.length == 50 && result[44] == 1 && result[48] == 3,
    'audio chunks become PCM WAV',
  );
  check(socket.closed, 'voice socket cleanup');
  final session = socket.sent.first['session'] as Map;
  check(
    session['audio']['input']['turn_detection'] == null,
    'no automatic microphone response',
  );
  check(
    session['audio']['output']['voice'] == 'coral' &&
        (session['tools'] as List).isEmpty,
    'voice style and no side effects',
  );
  final response = socket.sent.last['response'] as Map;
  check(
    response['conversation'] == 'none' &&
        (response['input'] as List).length == 1,
    'no accumulating voice context',
  );
  for (final mode in ['error', 'incomplete', 'disconnect']) {
    final bad = ScriptedVoiceSocket(mode);
    try {
      await OpenAiVoice(connector: (_, _, _) async => bad).speak(
        '你好',
        key: 'test-only',
        style: VoiceStyle.quiet,
        cancellation: TurnCancellation(),
      );
      throw StateError('Partial or failed audio accepted');
    } on VoiceFailure catch (e) {
      check(!e.message.contains('never-show'), 'redacted voice error');
    }
    check(bad.closed, 'failed socket closed');
  }
  final stalled = ScriptedVoiceSocket('stall');
  final token = TurnCancellation();
  final pending = OpenAiVoice(connector: (_, _, _) async => stalled).speak(
    '你好',
    key: 'test-only',
    style: VoiceStyle.bright,
    cancellation: token,
  );
  await Future<void>.delayed(const Duration(milliseconds: 5));
  token.cancel();
  try {
    await pending;
    throw StateError('Cancellation ignored');
  } on ChatFailure {}
  check(stalled.closed, 'cancel destroys socket');
  final timed = ScriptedVoiceSocket('stall');
  try {
    await OpenAiVoice(
      connector: (_, _, _) async => timed,
      timeout: const Duration(milliseconds: 5),
    ).speak(
      '你好',
      key: 'test-only',
      style: VoiceStyle.sweet,
      cancellation: TurnCancellation(),
    );
    throw StateError('Timeout ignored');
  } on VoiceFailure {}
  check(timed.closed, 'timeout destroys socket');
  print(
    'PASS: transcription multipart/auth/redaction, current Realtime voice events, bounded PCM, cancellation, timeout and no partial playback.',
  );
}

Future<void> main() => runVoiceChecks();
