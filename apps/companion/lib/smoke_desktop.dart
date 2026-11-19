// Offline screenshot/alpha checks in Flutter's headless engine; excluded from releases.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'main.dart';
import 'core.dart';
import 'smoke.dart' as smoke;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final failures = <String>[];
  FlutterError.onError = (d) {
    failures.add(d.toString());
    stderr.writeln(d);
  };
  final timeout = Timer(const Duration(seconds: 60), () => exit(1));
  final dir = await Directory.systemTemp.createTemp('alice-desktop-ui-');
  try {
    final core = NativeCore(
      '${dir.path}/state.sqlite3',
      Platform.environment['ALICE_CORE_LIBRARY']!,
    );
    await core.call({'op': 'select_persona', 'id': 'gentle_resolute'});
    final out = Directory(
      Platform.environment['ALICE_ARTIFACT_DIR'] ?? '/tmp/alice-desktop-ui',
    );
    await out.create(recursive: true);
    runApp(
      Directionality(
        textDirection: TextDirection.ltr,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 500,
          maxWidth: 500,
          minHeight: 780,
          maxHeight: 780,
          child: RepaintBoundary(
            key: smoke.surface,
            child: SizedBox(
              width: 500,
              height: 780,
              child: AliceApp(core: core, desktop: true),
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 10));
    await smoke.capture('transparent-desktop', out);
    final image =
        await (smoke.surface.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    smoke.check(bytes!.getUint8(3) == 0, 'Desktop background is opaque');
    var opaque = 0;
    for (var i = 3; i < bytes.lengthInBytes; i += 4) {
      if (bytes.getUint8(i) > 100) opaque++;
    }
    smoke.check(
      opaque > 10000 && opaque < image.width * image.height / 2,
      'Pet missing or too much opaque background',
    );
    image.dispose();
    await smoke.drawer('俄罗斯方块');
    await smoke.tapKey('arcade-start');
    await smoke.tapKey('arcade-drop');
    await smoke.capture('tetris', out);
    await smoke.tapKey('arcade-pause');
    smoke.check(smoke.hasText('暂停一下'), 'Pause overlay missing');
    await smoke.tapKey('close-arcade');
    await smoke.drawer('打砖块');
    await smoke.tapKey('arcade-start');
    await smoke.tapKey('arcade-drop');
    await smoke.capture('breakout', out);
    await smoke.tapKey('close-arcade');
    smoke.check(failures.isEmpty, failures.join('\n'));
    stdout.writeln(
      'PASS: transparent idle canvas contains only the pet, Tetris and Breakout launch, render, pause and close.',
    );
    timeout.cancel();
    exit(0);
  } catch (e, st) {
    stderr.writeln('$e\n$st');
    timeout.cancel();
    exit(1);
  }
}
