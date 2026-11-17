// Standalone Flutter-engine smoke runner. No server socket, no API requests.
// This entry point is only built by scripts/check-ui.sh, never by release builds.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'main.dart';
import 'core.dart';
import 'agent.dart';
import 'character_animation.dart';
import 'openai.dart';

final surface = GlobalKey();
final failures = <String>[];
void check(bool ok, String reason) {
  if (!ok) {
    throw StateError(reason);
  }
}

Iterable<Element> elements(Element root) sync* {
  yield root;
  final children = <Element>[];
  root.visitChildElements(children.add);
  for (final child in children) {
    yield* elements(child);
  }
}

Element? find(bool Function(Widget) predicate) {
  final root = surface.currentContext;
  if (root == null) {
    return null;
  }
  for (final e in elements(root as Element)) {
    if (predicate(e.widget)) {
      return e;
    }
  }
  return null;
}

bool hasText(String label) => find((w) => w is Text && w.data == label) != null;
Future<void> until(bool Function() predicate) async {
  for (var i = 0; i < 120; i++) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw StateError('UI did not reach the expected state');
}

Future<void> press(Element? e, String label) async {
  check(e != null, 'Missing control: $label');
  await Scrollable.ensureVisible(
    e!,
    duration: const Duration(milliseconds: 30),
  );
  VoidCallback? action;
  bool accept(Widget w) {
    if (w is ButtonStyleButton) {
      action = w.onPressed;
      return false;
    }
    if (w is IconButton) {
      action = w.onPressed;
      return false;
    }
    if (w is ListTile) {
      action = w.onTap;
      return false;
    }
    if (w is InkWell) {
      action = w.onTap;
      return false;
    }
    return true;
  }

  if (accept(e.widget)) e.visitAncestorElements((a) => accept(a.widget));
  check(action != null, 'Disabled control: $label');
  action!();
  await Future<void>.delayed(const Duration(milliseconds: 400));
}

Future<void> tapText(String label) =>
    press(find((w) => w is Text && w.data == label), label);
Future<void> tapKey(String key) =>
    press(find((w) => w.key == ValueKey<String>(key)), key);
Future<void> tapIcon(String label) =>
    press(find((w) => w is IconButton && w.tooltip == label), label);
Future<void> drawer(String label) async {
  await tapKey('more');
  await tapText(label);
}

PetMotion get activeMotion =>
    (find((w) => w is PetCharacter)!.widget as PetCharacter).motion;
void fill(String key, String value) {
  (find((w) => w is TextField && w.key == ValueKey<String>(key))!.widget
              as TextField)
          .controller!
          .text =
      value;
}

Future<void> capture(String name, Directory output) async {
  await Future<void>.delayed(const Duration(milliseconds: 150));
  await WidgetsBinding.instance.endOfFrame;
  final boundary =
      surface.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(
    '${output.path}/$name.png',
  ).writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
}

final smokeTransport = SmokeTransport();
Future<void> mount(CompanionCore core, double width, double height) async {
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: width,
        maxWidth: width,
        minHeight: height,
        maxHeight: height,
        child: RepaintBoundary(
          key: surface,
          child: SizedBox(
            width: width,
            height: height,
            child: AliceApp(
              core: core,
              agent: CompanionAgent(transport: smokeTransport),
            ),
          ),
        ),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    failures.add(details.toString());
    stderr.writeln(details);
  };
  final timeout = Timer(const Duration(seconds: 75), () {
    stderr.writeln('UI check timed out');
    exit(1);
  });
  final root = await Directory.systemTemp.createTemp('alice-ui-');
  try {
    final core = NativeCore(
      '${root.path}/state.sqlite3',
      Platform.environment['ALICE_CORE_LIBRARY']!,
    );
    final output = Directory(
      Platform.environment['ALICE_ARTIFACT_DIR'] ?? '/tmp/alice-ui',
    );
    await output.create(recursive: true);
    await mount(core, 480, 760);
    await until(() => hasText('选择她的性格'));
    await capture('welcome', output);
    check(
      find((w) => w is TextField) == null,
      'Home must not show input/settings by default',
    );
    await tapText('选择她的性格');
    await tapKey('gentle_resolute');
    await until(() => hasText('聊聊'));
    await Future<void>.delayed(const Duration(seconds: 3));
    await capture('companion-desktop', output);
    await tapIcon('摸摸');
    check(activeMotion == PetMotion.happy, 'Touch happy');
    await capture('animation-happy', output);
    await tapIcon('喝茶');
    check(activeMotion == PetMotion.tea, 'Tea scene');
    await capture('animation-tea', output);
    await tapIcon('休息');
    check(activeMotion == PetMotion.sleeping, 'Rest scene');
    await capture('animation-sleeping', output);
    await tapIcon('醒来');
    check(activeMotion == PetMotion.greeting, 'Wake scene');
    await drawer('我们的记忆');
    fill('memory-input', '我喜欢海边。倾诉时，希望先被认真倾听。');
    await tapText('记住这件事');
    var snap = await core.call({'op': 'snapshot'});
    check(snap['state']['memories'].length == 1, 'Manual memory saved');
    await tapKey('close-panel');
    await drawer('相处方式');
    await tapKey('reserved_attentive');
    snap = await core.call({'op': 'snapshot'});
    check(
      snap['state']['persona'] == 'reserved_attentive' &&
          snap['state']['memories'].length == 1,
      'Switch preserves memories',
    );
    await drawer('找珍珠');
    await tapText('藏好珍珠');
    await tapText('1');
    await tapKey('close-panel');
    // Dialog controllers must survive dismissal animations and repeated reopening.
    for (var i = 0; i < 3; i++) {
      await drawer('连接 OpenAI');
      await tapText('稍后再说');
    }
    await drawer('连接 OpenAI');
    fill('api-key', 'sk-proj-smoke-placeholder');
    fill('api-model', 'test-model');
    await tapText('保存设置');
    await tapIcon('聊聊');
    await Future<void>.delayed(const Duration(seconds: 3));
    check(activeMotion == PetMotion.listening, 'Focus enters listening');
    fill('chat-input', '我喜欢热可可，想请你记住。');
    await tapKey('send');
    check(activeMotion == PetMotion.thinking, 'Sending enters thinking');
    await capture('animation-thinking', output);
    await until(() => hasText('有件事，想问问你能不能记住'));
    check(
      activeMotion == PetMotion.listening,
      'Tool selects expression after final reply',
    );
    await capture('chat-desktop', output);
    await tapText('有件事，想问问你能不能记住');
    check(
      (await core.call({'op': 'snapshot'}))['state']['memories'].length == 1,
      'Proposal not silently stored',
    );
    await tapText('确认记住');
    check(
      (await core.call({'op': 'snapshot'}))['state']['memories'].length == 2,
      'Explicit memory approval',
    );
    await tapKey('close-panel');
    fill('chat-input', '失败后请保留这句');
    await tapKey('send');
    await until(() => activeMotion != PetMotion.thinking);
    check(
      (find(
                    (w) =>
                        w is TextField && w.key == const ValueKey('chat-input'),
                  )!.widget
                  as TextField)
              .controller!
              .text ==
          '失败后请保留这句',
      'Failure preserves draft',
    );
    fill('chat-input', '停止后也请保留');
    await tapKey('send');
    await tapKey('send');
    await until(() => activeMotion != PetMotion.thinking);
    check(
      (find(
                    (w) =>
                        w is TextField && w.key == const ValueKey('chat-input'),
                  )!.widget
                  as TextField)
              .controller!
              .text ==
          '停止后也请保留',
      'Cancellation preserves draft',
    );
    await tapIcon('收起聊天');
    check(
      PetMotion.idle.frameAt(2900) != PetMotion.idle.frameAt(0),
      'Idle uses different sprite frames',
    );
    runApp(const SizedBox());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await mount(core, 390, 700);
    await until(() => hasText('聊聊'));
    await capture('companion-mobile', output);
    await drawer('我们的记忆');
    await capture('memory-mobile', output);
    await tapKey('close-panel');
    await drawer('说过的话');
    await capture('history-mobile', output);
    await tapKey('close-panel');
    runApp(const SizedBox());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await mount(core, 320, 520);
    await until(() => hasText('聊聊'));
    await tapIcon('聊聊');
    await capture('companion-small', output);
    check(
      failures.isEmpty,
      'Flutter reported ${failures.length} layout/rendering errors',
    );
    stdout.writeln(
      'PASS: simple UI, seven motion scenes, tea/game, memory approval, settings dismiss/reopen, chat failure/cancel, restart and three viewport sizes.',
    );
    stdout.writeln('Screenshots: ${output.path}');
    runApp(const SizedBox());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await root.delete(recursive: true);
    timeout.cancel();
    exit(0);
  } catch (e, st) {
    stderr.writeln(e);
    stderr.writeln(st);
    timeout.cancel();
    exit(1);
  }
}

class SmokeTransport extends OpenAiChat {
  int calls = 0;
  @override
  Future<Map<String, dynamic>> respond({
    required String key,
    required String model,
    required Map<String, dynamic> request,
    TurnCancellation? cancellation,
  }) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    cancellation?.check();
    if (calls >= 3) throw ChatFailure('模拟断网，输入已保留。');
    return {
      'status': 'completed',
      'output': calls == 1
          ? [
              {
                'type': 'function_call',
                'call_id': 'm1',
                'name': 'propose_memory',
                'arguments': '{"content":"我喜欢热可可。"}',
              },
              {
                'type': 'function_call',
                'call_id': 'm2',
                'name': 'play_animation',
                'arguments': '{"animation":"listening"}',
              },
            ]
          : [
              {
                'type': 'message',
                'role': 'assistant',
                'content': [
                  {
                    'type': 'output_text',
                    'text': '热可可，记在小本子的候选页上了。等你点头，我再把它留下。今天的你，想聊点什么？',
                  },
                ],
              },
            ],
    };
  }
}
