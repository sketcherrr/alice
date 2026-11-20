import 'dart:convert';
import 'dart:io';
import 'package:dbus/dbus.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alice_companion/device_mode.dart';
import 'package:alice_companion/character_animation.dart';
import 'package:alice_companion/local_library.dart';
import 'package:alice_companion/wifi.dart';
import 'package:alice_companion/main.dart';
import 'widget_test.dart' show DemoCore, tapReady;

void main() {
  test('5 GHz is distinct from 2.4 GHz even with the same SSID', () {
    final five = wifiSettings(
      utf8.encode('小鲸鱼'),
      5180,
      'wpa-psk',
      'test-only-password',
    );
    final two = wifiSettings(
      utf8.encode('小鲸鱼'),
      2437,
      'wpa-psk',
      'test-only-password',
    );
    expect(five['802-11-wireless']!['band'], const DBusString('a'));
    expect(two['802-11-wireless']!['band'], const DBusString('bg'));
    expect(five['connection']!['id'], isNot(two['connection']!['id']));
    expect(five['connection']!['autoconnect'], const DBusBoolean(true));
    expect(wifiBand(5500), '5GHz');
    expect(wifiBand(5975), '6GHz');
    expect(
      wifiSettings([65], 5180, 'open', '')['802-11-wireless-security'],
      isNull,
    );
    expect(
      () => wifiSettings([65], 5180, 'wpa-psk', 'short'),
      throwsStateError,
    );
  });
  test(
    'import copies music, deduplicates, survives reopening and removes only its copy',
    () async {
      final temp = await Directory.systemTemp.createTemp('alice-library-test-');
      try {
        final source = File('${temp.path}/my song.wav');
        await source.writeAsBytes([
          ...ascii.encode('RIFF'),
          36,
          0,
          0,
          0,
          ...ascii.encode('WAVE'),
          ...List.filled(32, 0),
        ]);
        final library = LocalLibrary(Directory('${temp.path}/music'));
        await library.load();
        final first = await library.import(XFile(source.path));
        expect(first, 0);
        expect(await library.import(XFile(source.path)), 0);
        expect(library.tracks.length, 1);
        final reopened = LocalLibrary(library.root);
        await reopened.load();
        expect(
          await File(reopened.path(reopened.tracks.single)).readAsBytes(),
          await source.readAsBytes(),
        );
        await reopened.remove(0);
        expect(await source.exists(), true);
        await library.load();
        expect(library.tracks, isEmpty);
        final bad = File('${temp.path}/bad.mp3');
        await bad.writeAsString('not an audio file at all');
        await expectLater(library.import(XFile(bad.path)), throwsStateError);
        expect(library.tracks, isEmpty);
        expect(await File('${library.root.path}/import.tmp').exists(), false);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'device standby wakes with one touch and does not obscure an open panel',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('alice-device-test-');
      final prefs = DevicePreferences(temp)..idleSeconds = 30;
      final signal = ValueNotifier(0);
      Widget room(bool occupied) => MaterialApp(
        home: DeviceRoom(
          preferences: prefs,
          motion: PetMotion.idle,
          bubble: '你好',
          chosen: true,
          occupied: occupied,
          controls: const Text('听歌'),
          onPet: () {},
          onMore: () {},
          onChoose: () {},
          wakeSignal: signal,
        ),
      );
      await tester.pumpWidget(room(false));
      await tester.pump(const Duration(seconds: 31));
      expect(find.byKey(const ValueKey('standby-wake')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('standby-wake')));
      await tester.pump();
      expect(find.byKey(const ValueKey('standby-wake')), findsNothing);
      await tester.pumpWidget(room(true));
      await tester.pump(const Duration(seconds: 40));
      expect(find.byKey(const ValueKey('standby-wake')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      prefs.dispose();
      signal.dispose();
      temp.deleteSync(recursive: true);
    },
  );
  testWidgets(
    'device screen keeps care actions in drawer and renders at touch-screen size',
    (tester) async {
      tester.view.physicalSize = const Size(540, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final core = DemoCore();
      core.state['persona'] = 'gentle_resolute';
      await tester.pumpWidget(AliceApp(core: core, deviceMode: true));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('device-room')), findsOneWidget);
      await tapReady(tester, find.byTooltip('照顾她'));
      await tapReady(tester, find.byKey(const ValueKey('care-feed')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.widget<PetCharacter>(find.byType(PetCharacter)).motion,
        PetMotion.feeding,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
