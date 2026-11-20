// Real Flutter rendering + real Rust/SQLite, no microphone, Wi-Fi mutation or API.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dbus/dbus.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'audio_companion.dart';
import 'character_animation.dart';
import 'core.dart';
import 'device_mode.dart';
import 'main.dart';
import 'smoke.dart' as smoke;
import 'wifi.dart';

class _Audio extends NativeAudioDevice {
  String? played;
  @override
  Future<void> musicFile(String path, double volume) async {
    played = path;
  }

  @override
  Future<void> pauseMusic() async {}
  @override
  Future<void> close() async {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final failures = <String>[];
  FlutterError.onError = (d) {
    failures.add(d.toString());
    stderr.writeln(d);
  };
  final timeout = Timer(const Duration(seconds: 60), () => exit(1));
  final temp = await Directory.systemTemp.createTemp('alice-device-smoke-');
  final out = Directory(
    Platform.environment['ALICE_ARTIFACT_DIR'] ?? '/tmp/alice-device-ui',
  );
  final player = _Audio();
  final audio = CompanionAudio(device: player);
  try {
    await out.create(recursive: true);
    final core = NativeCore(
      '${temp.path}/state.sqlite3',
      Platform.environment['ALICE_CORE_LIBRARY']!,
    );
    await core.call({'op': 'select_persona', 'id': 'gentle_resolute'});
    void show() => runApp(
      Directionality(
        textDirection: TextDirection.ltr,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 540,
          maxWidth: 540,
          minHeight: 860,
          maxHeight: 860,
          child: RepaintBoundary(
            key: smoke.surface,
            child: SizedBox(
              width: 540,
              height: 860,
              child: AliceApp(core: core, audio: audio, deviceMode: true),
            ),
          ),
        ),
      ),
    );
    show();
    await smoke.until(() => smoke.find((w) => w is DeviceRoom) != null);
    await Future<void>.delayed(const Duration(seconds: 2));
    await smoke.capture('device-welcome', out);
    await smoke.tapIcon('照顾她');
    await smoke.capture('care-panel', out);
    await smoke.tapKey('care-feed');
    await smoke.until(
      () =>
          (smoke.find((w) => w is PetCharacter)?.widget as PetCharacter?)
              ?.motion ==
          PetMotion.feeding,
    );
    smoke.check(
      (await core.call({'op': 'snapshot'}))['state']['satiety'] > 94,
      'feed did not persist',
    );
    await smoke.capture('feeding', out);
    await smoke.tapIcon('照顾她');
    await smoke.tapKey('care-bath');
    await smoke.until(
      () =>
          (smoke.find((w) => w is PetCharacter)?.widget as PetCharacter?)
              ?.motion ==
          PetMotion.bathing,
    );
    smoke.check(
      (await core.call({'op': 'snapshot'}))['state']['cleanliness'] > 99,
      'bath did not persist',
    );
    await smoke.capture('bathing', out);
    await smoke.tapIcon('照顾她');
    await smoke.tapKey('care-sleep');
    await smoke.until(
      () =>
          (smoke.find((w) => w is PetCharacter)?.widget as PetCharacter?)
              ?.motion ==
          PetMotion.sleeping,
    );
    runApp(const SizedBox());
    await Future<void>.delayed(const Duration(milliseconds: 200));
    show();
    await smoke.until(
      () =>
          (smoke.find((w) => w is PetCharacter)?.widget as PetCharacter?)
              ?.motion ==
          PetMotion.sleeping,
    );
    await smoke.capture('sleep-restored', out);
    await smoke.tapIcon('照顾她');
    await smoke.tapKey('care-sleep');
    await smoke.until(
      () =>
          (smoke.find((w) => w is PetCharacter)?.widget as PetCharacter?)
              ?.motion ==
          PetMotion.greeting,
    );
    await smoke.tapKey('device-more');
    await smoke.tapText('待机与欢迎');
    await smoke.until(
      () =>
          smoke.find(
            (w) => w is TextField && w.key == const ValueKey('welcome-text'),
          ) !=
          null,
    );
    smoke.fill('welcome-text', '回来啦，今天也一起摸鱼。');
    await smoke.tapText('就这样，保存');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final room = smoke.find((w) => w is DeviceRoom)!.widget as DeviceRoom;
    final prefs = DevicePreferences(temp);
    await prefs.load();
    smoke.check(prefs.welcome == '回来啦，今天也一起摸鱼。', 'welcome preference lost');
    prefs.dispose();
    room.preferences.idleSeconds = 1;
    await smoke.until(
      () => smoke.find((w) => w.key == const ValueKey('standby-wake')) != null,
    );
    await smoke.capture('standby', out);
    final wake =
        smoke.find((w) => w.key == const ValueKey('standby-wake'))!.widget
            as GestureDetector;
    wake.onTap!();
    room.preferences.idleSeconds = 60;
    await smoke.until(
      () => smoke.find((w) => w.key == const ValueKey('standby-wake')) == null,
    );
    final source = File('${temp.path}/点心时间.wav');
    await source.writeAsBytes([
      ...ascii.encode('RIFF'),
      36,
      0,
      0,
      0,
      ...ascii.encode('WAVE'),
      ...List.filled(32, 0),
    ]);
    await audio.importMusic(XFile(source.path));
    smoke.check(audio.error == null, audio.error ?? '');
    await audio.importMusic(XFile(source.path));
    smoke.check(audio.trackCount == 3, 'duplicate import');
    await audio.toggleMusic();
    smoke.check(
      player.played != null && player.played != source.path,
      'not playing managed copy',
    );
    await audio.toggleMusic();
    await smoke.tapIcon('听歌');
    await smoke.capture('local-music', out);
    await smoke.tapKey('close-panel');
    final again = CompanionAudio(device: _Audio());
    await audio.shutdown();
    await again.loadPreferences(File('${temp.path}/audio.json'));
    smoke.check(
      again.trackCount == 3 && again.trackTitle(2) == '点心时间',
      'music not restored',
    );
    await again.removeTrack(2);
    smoke.check(await source.exists(), 'removed original');
    again.dispose();
    final five = wifiSettings(
      utf8.encode('Alice WiFi'),
      5180,
      'wpa-psk',
      'test-only-pass',
    );
    final two = wifiSettings(
      utf8.encode('Alice WiFi'),
      2437,
      'wpa-psk',
      'test-only-pass',
    );
    smoke.check(
      five['802-11-wireless']!['band'] == const DBusString('a') &&
          two['802-11-wireless']!['band'] == const DBusString('bg'),
      '5 GHz selection lost',
    );
    smoke.check(
      five['connection']!['id'] != two['connection']!['id'],
      'same-name dual-band profiles merged',
    );
    smoke.check(failures.isEmpty, failures.join('\n'));
    runApp(const SizedBox());
    await Future<void>.delayed(const Duration(milliseconds: 200));
    stdout.writeln(
      'PASS: device rendering, care actions, sleep restart, welcome persistence, standby/wake, music import/dedup/reopen/removal and distinct 5GHz profile. No real Wi-Fi or audio device used.',
    );
    timeout.cancel();
    audio.dispose();
    await temp.delete(recursive: true);
    exit(0);
  } catch (e, st) {
    stderr.writeln('$e\n$st');
    timeout.cancel();
    exit(1);
  }
}
