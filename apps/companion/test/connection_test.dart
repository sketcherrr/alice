import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alice_companion/connection_dialog.dart';
import 'package:alice_companion/openai.dart';
import 'package:alice_companion/openai_network.dart';

void main() {
  testWidgets('diagnostic stays visible and checking does not save settings', (
    tester,
  ) async {
    final original = OpenAiNetwork.settings;
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectionDialog(
            initialKey: 'test-only',
            initialModel: 'gpt-6-astra',
            checker: (key, model, network, token) async {
              calls++;
              expect(key, 'test-only');
              expect(model, 'gpt-6-astra');
              throw ChatFailure(
                'API 额度不足\nHTTP 429 · insufficient_quota',
                statusCode: 429,
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('check-connection')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('connection-report')),
          )
          .data,
      contains('insufficient_quota'),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(find.byKey(const ValueKey('connection-report')), findsOneWidget);
    expect(identical(original, OpenAiNetwork.settings), isTrue);
  });
  testWidgets('closing settings cancels diagnostic and ignores a late reply', (
    tester,
  ) async {
    final result = Completer<String>();
    TurnCancellation? token;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConnectionDialog(
            initialKey: 'test-only',
            initialModel: 'gpt-6-astra',
            checker: (key, model, network, cancellation) {
              token = cancellation;
              return result.future;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('check-connection')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存设置'))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    expect(token!.cancelled, isTrue);
    result.complete('late reply');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
