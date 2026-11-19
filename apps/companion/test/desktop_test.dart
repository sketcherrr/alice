import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alice_companion/main.dart';
import 'package:alice_companion/desktop_pet.dart';
import 'widget_test.dart' show DemoCore, tapReady;

void main() {
  testWidgets(
    'desktop idle has transparent pixels and panels expand then collapse',
    (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DesktopHost.channel,
        (call) async {
          calls.add('${call.method}:${call.arguments}');
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          DesktopHost.channel,
          null,
        ),
      );
      tester.view.physicalSize = const Size(500, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final core = DemoCore();
      core.state['persona'] = 'gentle_resolute';
      final surface = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: surface,
          child: AliceApp(core: core, desktop: true),
        ),
      );
      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(milliseconds: 500));
      final scaffold = tester.widget<Scaffold>(
        find.byKey(const ValueKey('transparent-desktop')),
      );
      expect(scaffold.backgroundColor, Colors.transparent);
      await tester.runAsync(() async {
        final image =
            await (surface.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        expect(
          data!.getUint8(3),
          0,
          reason: 'Top-left corner must contain zero background alpha',
        );
        expect(
          data.getUint8(
            ((image.height - 1) * image.width + image.width - 1) * 4 + 3,
          ),
          0,
        );
        image.dispose();
      });
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('pet'))));
      await tester.pump(const Duration(milliseconds: 300));
      await tapReady(tester, find.byKey(const ValueKey('more')));
      expect(calls, contains('expanded:true'));
      expect(find.text('俄罗斯方块'), findsOneWidget);
      expect(find.text('打砖块'), findsOneWidget);
      await tapReady(tester, find.byKey(const ValueKey('close-panel')));
      await tester.pump(const Duration(seconds: 1));
      expect(calls, contains('expanded:false'));
      // Disposing during the route's close animation must cancel resizing.
      await tapReady(tester, find.byKey(const ValueKey('more')));
      await tapReady(tester, find.byKey(const ValueKey('close-panel')));
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
