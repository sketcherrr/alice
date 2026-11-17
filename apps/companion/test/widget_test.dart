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
        await tester.tap(find.text('选择她的性格'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byKey(const ValueKey('gentle_resolute')));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byTooltip('摸摸'));
        await tester.pump();
        expect(
          tester.widget<PetCharacter>(find.byType(PetCharacter)).motion,
          PetMotion.happy,
        );
        await tester.tap(find.byTooltip('休息'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester.widget<PetCharacter>(find.byType(PetCharacter)).motion,
          PetMotion.sleeping,
        );
        await tester.tap(find.byTooltip('醒来'));
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
