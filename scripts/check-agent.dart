// Deterministic agent integration checks: real Rust/SQLite, simulated HTTP only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../apps/companion/lib/agent.dart';
import '../apps/companion/lib/core.dart';
import '../apps/companion/lib/openai.dart';
import 'check-offline.dart' show Client, check;

Map<String, dynamic> call(String id, String name, String args) => {
  'type': 'function_call',
  'id': 'fc_$id',
  'call_id': id,
  'name': name,
  'arguments': args,
  'status': 'completed',
};
Map<String, dynamic> reply(String text) => {
  'type': 'message',
  'id': 'msg_test',
  'role': 'assistant',
  'status': 'completed',
  'phase': 'final_answer',
  'content': [
    {'type': 'output_text', 'text': text, 'annotations': []},
  ],
};

class Scripted {
  final List<Client> clients;
  int cursor = 0;
  Scripted(List<List<Map<String, dynamic>>> outputs)
    : clients = outputs
          .map(
            (o) =>
                Client(200, jsonEncode({'status': 'completed', 'output': o})),
          )
          .toList();
  OpenAiChat get transport => OpenAiChat(
    clientFactory: () {
      check(cursor < clients.length, 'unexpected extra API request');
      return clients[cursor++];
    },
  );
  Map<String, dynamic> body(int i) =>
      jsonDecode(utf8.decode(clients[i].request.bytes));
}

Future<void> mustFail(Future<dynamic> Function() body) async {
  var failed = false;
  try {
    await body();
  } on ChatFailure {
    failed = true;
  } on StateError {
    failed = true;
  }
  check(failed, 'expected rejected turn');
}

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('alice-agent-');
  final lib =
      Platform.environment['ALICE_CORE_LIBRARY'] ??
      File('target/release/libalice_core.so').absolute.path;
  final core = NativeCore('${root.path}/state.sqlite3', lib);
  Future<Map<String, dynamic>> state() async =>
      (await core.call({'op': 'snapshot'}))['state'];
  Future<AgentResult> run(
    Scripted script, {
    String text = '我喜欢热可可，请记住。你还记得我喜欢哪里吗？',
    int maxRequests = 5,
    int maxToolCalls = 8,
    TurnCancellation? token,
    void Function(String)? progress,
  }) =>
      CompanionAgent(
        transport: script.transport,
        maxRequests: maxRequests,
        maxToolCalls: maxToolCalls,
      ).run(
        core: core,
        text: text,
        key: 'sk-proj-test-placeholder',
        model: 'test-model',
        cancellation: token ?? TurnCancellation(),
        onProgress: progress,
      );
  try {
    await core.call({'op': 'select_persona', 'id': 'gentle_resolute'});
    await core.call({'op': 'remember', 'content': '我喜欢海边。'});
    final reasoning = {
      'type': 'reasoning',
      'id': 'rs_test',
      'summary': <dynamic>[],
      'encrypted_content': 'opaque-test-data',
    };
    final script = Scripted([
      [
        reasoning,
        {...reply('我翻翻小本子。'), 'phase': 'commentary'},
        call('one', 'search_memories', '{"query":"海边"}'),
      ],
      [call('two', 'propose_memory', '{"content":"我喜欢热可可。"}')],
      [call('three', 'play_animation', '{"animation":"listening"}')],
      [reply('记得，你喜欢海边。热可可这件事也想留下吗？')],
    ]);
    final result = await run(script);
    check(result.requests == 4 && result.toolCalls == 3, 'complete tool loop');
    check(
      result.animation == 'listening' &&
          result.memoryProposals.single == '我喜欢热可可。',
      'staged UI effects',
    );
    check(
      (result.state['memories'] as List).length == 1,
      'proposal must not become a saved fact',
    );
    final first = script.body(0), second = script.body(1);
    check(
      first['store'] == false && first['parallel_tool_calls'] == false,
      'stateless sequential calls',
    );
    check(
      first['tools'].length == 4 &&
          first['tools'].every(
            (t) =>
                t['strict'] == true &&
                t['parameters']['additionalProperties'] == false,
          ),
      'strict schemas',
    );
    check(
      script.clients.first.request.headers.values['authorization'] ==
          'Bearer sk-proj-test-placeholder',
      'project key format',
    );
    final replay = second['input'] as List;
    check(
      replay.any((x) => x['encrypted_content'] == 'opaque-test-data'),
      'encrypted reasoning preserved',
    );
    check(
      replay.any((x) => x['phase'] == 'commentary'),
      'message phase preserved',
    );
    final output = replay.last;
    check(
      output['type'] == 'function_call_output' && output['call_id'] == 'one',
      'call ID correlation',
    );
    check(
      jsonDecode(output['output'])['memories'][0]['content'] == '我喜欢海边。',
      'actual memory retrieval',
    );
    check(
      (result.state['messages'] as List)
              .where((m) => m['mode'] == 'online')
              .length ==
          2,
      'atomic user/assistant commit',
    );
    print(
      'PASS: OpenAI schemas/auth, reasoning replay, tool outputs, real memory lookup, deferred memory, atomic commit.',
    );

    final executor = CompanionTools(await state());
    for (final args in [
      '{',
      '[]',
      '{}',
      '{"animation":"shell"}',
      '{"animation":"happy","extra":true}',
    ]) {
      check(
        executor.execute('play_animation', args)['ok'] == false,
        'invalid arguments rejected: $args',
      );
    }
    check(
      executor.execute('execute_shell', '{}')['error'] == 'unknown_tool',
      'unknown tools denied',
    );
    final malformed = Scripted([
      [call('bad', 'play_animation', '{')],
      [reply('我会安静陪你。')],
    ]);
    await run(malformed);
    check(
      jsonDecode(
            (malformed.body(1)['input'] as List).last['output'],
          )['error'] ==
          'invalid_json',
      'recoverable tool error returned to model',
    );
    final before = jsonEncode((await state())['messages']);
    final repeated = Scripted([
      [call('dup', 'propose_memory', '{"content":"不应保存的建议"}')],
      [call('dup', 'propose_memory', '{"content":"不应保存的建议"}')],
    ]);
    await mustFail(() => run(repeated));
    final loop = Scripted([
      [call('l1', 'get_companion_state', '{}')],
      [call('l2', 'get_companion_state', '{}')],
    ]);
    await mustFail(() => run(loop, maxRequests: 2));
    check(
      loop.body(1)['tool_choice'] == 'none',
      'force final reply at turn bound',
    );
    final many = Scripted([
      [
        call('a', 'get_companion_state', '{}'),
        call('b', 'get_companion_state', '{}'),
      ],
    ]);
    await mustFail(() => run(many, maxToolCalls: 1));
    check(
      jsonEncode((await state())['messages']) == before,
      'failed turns do not write chat',
    );
    print(
      'PASS: invalid JSON/schema/unknown functions, duplicate IDs, loop/call limits, failed-turn rollback.',
    );

    final cancellation = TurnCancellation();
    final cancelled = Scripted([
      [reply('不得写入')],
    ]);
    await mustFail(
      () => run(
        cancelled,
        token: cancellation,
        progress: (_) => cancellation.cancel(),
      ),
    );
    check(cancelled.cursor == 0, 'cancel before request');
    check(
      jsonEncode((await state())['messages']) == before,
      'cancelled turn not persisted',
    );
    // Simulate a settings change while a remote response is in flight.
    final changed = _MutatingTransport(core);
    await mustFail(
      () => CompanionAgent(transport: changed).run(
        core: core,
        text: '旧上下文',
        key: 'test',
        model: 'test',
        cancellation: TurnCancellation(),
      ),
    );
    check(
      jsonEncode((await state())['messages']) == before,
      'revision prevents stale reply commit',
    );
    print(
      'PASS: cancellation, no network after cancel, stale-context revision protection.',
    );

    for (var i = 0; i < 18; i++) {
      final question = '问题 $i ' + List.filled(80, '海边生活').join();
      final prepared = await core.call({
        'op': 'prepare_chat',
        'text': question,
      });
      await core.call({
        'op': 'commit_chat',
        'text': question,
        'answer': '回答 $i ' + List.filled(600, '轻轻的海风。').join(),
        'revision': prepared['revision'],
      });
    }
    final prepared = await core.call({'op': 'prepare_chat', 'text': '最新的提问'});
    final context = CompanionContext.build(prepared, '最新的提问');
    check(
      utf8.encode(jsonEncode(context)).length <=
          CompanionContext.maxContextBytes,
      'bounded context',
    );
    final items = context['input'] as List;
    check(items.last['content'] == '最新的提问', 'newest input retained');
    check(
      items.any((m) => (m['content'] as String).contains('截断原文摘录')),
      'bounded old-dialogue excerpts',
    );
    for (var i = 2; i < items.length - 1; i += 2) {
      check(
        items[i]['role'] == 'user' && items[i + 1]['role'] == 'assistant',
        'complete recent turns retained',
      );
    }
    final large = jsonDecode(jsonEncode(prepared)) as Map<String, dynamic>;
    large['request']['input'][0]['content'] = List.filled(9000, '记').join();
    final longQuestion = List.filled(4000, '问').join();
    final trimmed = CompanionContext.build(large, longQuestion);
    check(
      utf8.encode(jsonEncode(trimmed)).length <=
          CompanionContext.maxContextBytes,
      'large background trims old context to budget',
    );
    check(
      (trimmed['input'] as List).last['content'] == longQuestion,
      'budget trimming preserves entire current question',
    );
    final memory = (await state())['memories'][0];
    await core.call({'op': 'forget', 'id': memory['id']});
    final fresh = CompanionContext.build(
      await core.call({'op': 'prepare_chat', 'text': '新的话题'}),
      '新的话题',
    );
    check(
      !jsonEncode(fresh).contains('问题 17') &&
          !jsonEncode(fresh).contains('我喜欢海边。'),
      'forgotten facts and old excerpts excluded',
    );
    await core.call({'op': 'clear_chat'});
    check((await state())['messages'].isEmpty, 'clear history');
    print(
      'PASS: byte budget, complete turns, extractive context, forget invalidates history/excerpts.',
    );
  } finally {
    await root.delete(recursive: true);
  }
}

class _MutatingTransport extends OpenAiChat {
  final CompanionCore core;
  _MutatingTransport(this.core);
  @override
  Future<Map<String, dynamic>> respond({
    required String key,
    required String model,
    required Map<String, dynamic> request,
    TurnCancellation? cancellation,
  }) async {
    await core.call({'op': 'select_persona', 'id': 'reserved_attentive'});
    return {
      'status': 'completed',
      'output': [reply('旧回复')],
    };
  }
}
