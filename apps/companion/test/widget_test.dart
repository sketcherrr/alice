import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alice_companion/main.dart';
import 'package:alice_companion/core.dart';
import 'package:alice_companion/character_animation.dart';

class DemoCore implements CompanionCore {
  final profiles = ['gentle_resolute', 'clever_playful', 'reserved_attentive']
      .map(
        (id) => jsonDecode(
          File('../../assets/personas/$id.json').readAsStringSync(),
        ),
      )
      .toList();
  final state = <String, dynamic>{
    'persona': null,
    'messages': <dynamic>[],
    'memories': <dynamic>[],
    'events': <dynamic>[],
    'game': 'idle',
  };
  @override
  Future<Map<String, dynamic>> call(Map<String, dynamic> request) async {
    if (request['op'] == 'select_persona') state['persona'] = request['id'];
    if (request['op'] == 'remember')
      (state['memories'] as List).add({'id': 1, 'content': request['content']});
    return {'state': state, 'profiles': profiles};
  }
}

// The pet ticker intentionally never settles. Advance route animations until
// the actual pointer target is available instead of waiting for all animations.
Future<void> tapReady(WidgetTester tester, Finder finder) async {
  await tester.pump();
  for (var frame = 0; frame < 30; frame++) {
    if (finder.hitTestable().evaluate().length == 1) {
      await tester.tap(finder);
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Control did not become visible and hit-testable: $finder');
}

void main() {
  for (final width in [390.0, 480.0, 1280.0]) {
    testWidgets(
      'single character, explicit persona and scene animation at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final core = DemoCore();
        await tester.pumpWidget(AliceApp(core: core));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(PetCharacter), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        await tapReady(tester, find.text('选择她的性格'));
        await tapReady(tester, find.byKey(const ValueKey('gentle_resolute')));
        expect(core.state['persona'], 'gentle_resolute');
        await tapReady(tester, find.byTooltip('摸摸'));
        await tester.pump();
        expect(
          tester.widget<PetCharacter>(find.byType(PetCharacter)).motion,
          PetMotion.happy,
        );
        await tapReady(tester, find.byTooltip('休息'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester.widget<PetCharacter>(find.byType(PetCharacter)).motion,
          PetMotion.sleeping,
        );
        await tapReady(tester, find.byTooltip('醒来'));
        await tester.pump();
        expect(
          tester.widget<PetCharacter>(find.byType(PetCharacter)).motion,
          PetMotion.greeting,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
