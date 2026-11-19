import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alice_companion/arcade.dart';
import '../../../scripts/check-arcade.dart' as rules;

void main() {
  test('offline arcade rules', rules.runArcadeChecks);
  for (final kind in ArcadeKind.values) {
    testWidgets('${kind.name}: start, keyboard, pause, lifecycle and restart', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: ArcadeRoom(kind: kind, onResult: (_, _) async {}),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('arcade-start')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 100));
      if (kind == ArcadeKind.tetris) expect(find.text('得分 0'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pump();
      expect(find.text('暂停一下'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('arcade-start')));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('暂停一下'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('暂停一下'), findsOneWidget);
      await tester.tap(find.text('重新开始'));
      await tester.pump();
      expect(find.text('得分 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
