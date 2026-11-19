import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alice_companion/audio_companion.dart';
import 'package:alice_companion/sound_widgets.dart';
import 'package:alice_companion/voice_api.dart';
import 'package:alice_companion/openai.dart';
import 'package:alice_companion/main.dart';
import 'package:alice_companion/agent.dart';
import 'package:alice_companion/core.dart';
import 'widget_test.dart' show DemoCore, tapReady;
import '../../../scripts/check-voice.dart' as protocol;

class FakeAudioDevice implements CompanionAudioDevice {
  bool playing = false, recording = false, closed = false, allow = true;
  int starts = 0, plays = 0, cancels = 0;
  double musicGain = 0, voiceGain = 0;
  Completer<bool>? permission;
  Completer<void>? playback;
  @override
  Future<void> music(int track, double volume) async {
    playing = true;
    musicGain = volume;
  }

  @override
  Future<void> pauseMusic() async {
    playing = false;
  }

  @override
  Future<void> musicVolume(double value) async {
    musicGain = value;
  }

  @override
  Future<void> playVoice(Uint8List wav, double volume) async {
    plays++;
    voiceGain = volume;
    playback = Completer<void>();
    await playback!.future;
  }

  @override
  Future<void> stopVoice() async {
    if (playback != null && !playback!.isCompleted) playback!.complete();
  }

  @override
  Future<void> voiceVolume(double value) async {
    voiceGain = value;
  }

  @override
  Future<bool> microphonePermission() async =>
      permission == null ? allow : await permission!.future;
  @override
  Future<void> startRecording() async {
    starts++;
    recording = true;
  }

  @override
  Future<Uint8List?> stopRecording() async {
    recording = false;
    return Uint8List(100);
  }

  @override
  Future<void> cancelRecording() async {
    cancels++;
    recording = false;
  }

  @override
  Future<void> close() async {
    closed = true;
    await stopVoice();
    recording = false;
  }
}

class FakeVoice extends OpenAiVoice {
  final generated = Completer<Uint8List>();
  @override
  Future<Uint8List> speak(
    String text, {
    required String key,
    required VoiceStyle style,
    required TurnCancellation cancellation,
  }) => generated.future;
}

Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 10));

class RoundTripVoice extends OpenAiVoice {
  int transcriptions = 0;
  String? spoken;
  @override
  Future<String> transcribe(
    Uint8List wav, {
    required String key,
    required TurnCancellation cancellation,
  }) async {
    transcriptions++;
    return '今天有点累';
  }

  @override
  Future<Uint8List> speak(
    String text, {
    required String key,
    required VoiceStyle style,
    required TurnCancellation cancellation,
  }) async {
    spoken = text;
    return Uint8List(100);
  }
}

class RoundTripAgent extends CompanionAgent {
  @override
  Future<AgentResult> run({
    required CompanionCore core,
    required String text,
    required String key,
    required String model,
    required TurnCancellation cancellation,
    void Function(String)? onProgress,
  }) async {
    final state = (core as DemoCore).state;
    (state['messages'] as List).addAll([
      {'role': 'user', 'content': text},
      {'role': 'assistant', 'content': '那就歇一会儿，我陪你听音乐。'},
    ]);
    return AgentResult(state, [], null, 1, 0);
  }
}

void main() {
  testWidgets(
    'hold-to-talk goes through transcription, existing agent and spoken reply',
    (tester) async {
      final device = FakeAudioDevice(), api = RoundTripVoice();
      final audio = CompanionAudio(device: device, api: api);
      final core = DemoCore();
      core.state['persona'] = 'gentle_resolute';
      addTearDown(audio.dispose);
      await tester.pumpWidget(
        AliceApp(
          core: core,
          agent: RoundTripAgent(),
          audio: audio,
          desktop: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      // No key: the explicit recording action opens connection settings.
      await tester.tap(find.byKey(const ValueKey('hold-to-speak')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
        find.byKey(const ValueKey('api-key')),
        'test-only',
      );
      await tester.enterText(
        find.byKey(const ValueKey('api-model')),
        'test-model',
      );
      await tapReady(tester, find.text('保存设置'));
      await tester.pump(const Duration(milliseconds: 500));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('hold-to-speak'))),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.transcriptions, 1);
      expect((core.state['messages'] as List).first['content'], '今天有点累');
      expect(api.spoken, '那就歇一会儿，我陪你听音乐。');
      expect(device.plays, 1);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-input')))
            .controller!
            .text,
        isEmpty,
      );
      await audio.stopSpeech();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  test('offline speech protocol checks', protocol.runVoiceChecks);
  test('music ducks for voice and mutes for capture, then recovers', () async {
    final device = FakeAudioDevice();
    final api = FakeVoice();
    final audio = CompanionAudio(device: device, api: api);
    addTearDown(audio.dispose);
    await audio.toggleMusic();
    expect(device.musicGain, .3);
    final speech = audio.say('你好', 'test-only');
    await tick();
    expect(device.musicGain, closeTo(.066, .001));
    api.generated.complete(Uint8List(100));
    await tick();
    expect(audio.speaking, true);
    await audio.setVoiceLevel(.5);
    expect(device.voiceGain, .5);
    await audio.stopSpeech();
    await speech;
    expect(device.musicGain, .3);
    expect(audio.speaking, false);
    await audio.beginCapture();
    expect(device.musicGain, 0);
    expect(device.recording, true);
    await audio.cancelCapture();
    expect(device.recording, false);
    expect(device.musicGain, .3);
  });
  test(
    'release before permission resolves never starts a hidden recording',
    () async {
      final device = FakeAudioDevice()..permission = Completer<bool>();
      final audio = CompanionAudio(device: device);
      addTearDown(audio.dispose);
      final starting = audio.beginCapture();
      await tick();
      final released = audio.endCapture();
      device.permission!.complete(true);
      await starting;
      expect(await released, isNull);
      expect(device.starts, 0);
      expect(audio.recording, false);
      device.permission = null;
      device.allow = false;
      await audio.beginCapture();
      expect(audio.error, contains('权限'));
      expect(device.starts, 0);
    },
  );
  test(
    'late speech is ignored after cancellation and disposal closes devices',
    () async {
      final device = FakeAudioDevice();
      final api = FakeVoice();
      final audio = CompanionAudio(device: device, api: api);
      final speech = audio.say('你好', 'test-only');
      await tick();
      await audio.stopSpeech();
      api.generated.complete(Uint8List(100));
      await speech;
      expect(device.plays, 0);
      audio.dispose();
      await tick();
      expect(device.closed, true);
    },
  );
  test(
    'settings survive restart without storing a key or automatically playing',
    () async {
      final dir = await Directory.systemTemp.createTemp('alice-audio-test-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/audio.json');
      final a = CompanionAudio(device: FakeAudioDevice());
      await a.loadPreferences(file);
      await a.setMusicLevel(.6);
      a.setStyle(VoiceStyle.quiet);
      a.setAutoSpeak(false);
      await tick();
      a.dispose();
      await tick();
      final b = CompanionAudio(device: FakeAudioDevice());
      addTearDown(b.dispose);
      await b.loadPreferences(file);
      expect(b.musicLevel, .6);
      expect(b.style, VoiceStyle.quiet);
      expect(b.autoSpeak, false);
      expect(b.playing, false);
      expect(await file.readAsString(), isNot(contains('key')));
    },
  );
  testWidgets(
    'press/release and leaving the mic have distinct send/cancel actions',
    (tester) async {
      var starts = 0, ends = 0, cancels = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: HoldToSpeak(
              enabled: true,
              active: false,
              stopping: false,
              onStart: () => starts++,
              onEnd: () => ends++,
              onCancel: () => cancels++,
              onStop: () {},
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byType(HoldToSpeak));
      final first = await tester.startGesture(center);
      await first.up();
      expect(starts, 1);
      expect(ends, 1);
      expect(cancels, 0);
      final second = await tester.startGesture(center);
      await second.moveBy(const Offset(100, 0));
      await second.up();
      expect(starts, 2);
      expect(ends, 1);
      expect(cancels, 1);
    },
  );
  testWidgets(
    'sound controls fit narrow screens and music works without a key',
    (tester) async {
      final device = FakeAudioDevice();
      final audio = CompanionAudio(device: device);
      addTearDown(audio.dispose);
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: SoundPanel(
                  audio: audio,
                  onPreview: () {},
                  onConnect: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('music-toggle')));
      await tester.pump();
      expect(device.playing, true);
      expect(find.text('AI 合成语音 · 可爱的卡通女声'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
