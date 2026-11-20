import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'agent.dart';
import 'character_animation.dart';
import 'core.dart';
import 'openai.dart';
import 'desktop_pet.dart';
import 'arcade.dart';
import 'audio_companion.dart';
import 'sound_widgets.dart';
import 'device_mode.dart';
import 'wifi.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  final device =
      args.contains('--device') ||
      args.contains('--device-preview') ||
      ['1', 'preview'].contains(Platform.environment['ALICE_DEVICE_MODE']);
  runApp(
    AliceApp(desktop: DesktopHost.supported && !device, deviceMode: device),
  );
}

const ink = Color(0xFF494B68),
    muted = Color(0xFF8A8CA4),
    accent = Color(0xFF7B83B6);
const paper = Color(0xFFFCFAF8);

class AliceApp extends StatelessWidget {
  final CompanionCore? core;
  final CompanionAgent? agent;
  final bool desktop, deviceMode;
  final CompanionAudio? audio;
  const AliceApp({
    super.key,
    this.core,
    this.agent,
    this.audio,
    this.desktop = false,
    this.deviceMode = false,
  });
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Alice · 小小鲸屿',
    color: Colors.transparent,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: desktop ? Colors.transparent : paper,
      colorScheme: ColorScheme.fromSeed(seedColor: accent, surface: paper),
      fontFamily: 'Noto Sans CJK SC',
      textTheme: ThemeData.light().textTheme.apply(
        fontFamily: 'Noto Sans CJK SC',
        bodyColor: ink,
        displayColor: ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Color(0xFFE5E4EE)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Color(0xFFE5E4EE)),
        ),
      ),
    ),
    home: CompanionHome(
      core: core,
      agent: agent,
      audio: audio,
      desktop: desktop,
      deviceMode: deviceMode,
    ),
  );
}

class CompanionHome extends StatefulWidget {
  final CompanionCore? core;
  final CompanionAgent? agent;
  final bool desktop, deviceMode;
  final CompanionAudio? audio;
  const CompanionHome({
    super.key,
    this.core,
    this.agent,
    this.audio,
    this.desktop = false,
    this.deviceMode = false,
  });
  @override
  State<CompanionHome> createState() => _CompanionHomeState();
}

class _CompanionHomeState extends State<CompanionHome>
    with WidgetsBindingObserver {
  CompanionCore? core;
  Map<String, dynamic>? state;
  List<dynamic> profiles = [];
  String? startupError, localLine;
  String progress = '';
  bool busy = false, chatOpen = false, onTop = true;
  int panels = 0;
  Timer? idleTimer, panelResizeTimer, stateTimer;
  DevicePreferences? devicePreferences;
  final wakeSignal = ValueNotifier<int>(0);
  bool get sleeping => state?['sleeping'] == true;
  Future<bool> _wakePet() async {
    if (!sleeping) return true;
    final ok = await _run({'op': 'action', 'action': 'wake'});
    if (ok) {
      motion.sleep(false);
      motion.play(PetMotion.greeting);
    }
    return ok;
  }

  late final CompanionAudio audio;
  String? lastAudioError;
  int voiceGestureEpoch = 0;
  bool get capturing => audio.starting || audio.recording || audio.finishing;
  String keyValue = Platform.environment['OPENAI_API_KEY'] ?? '';
  String model = Platform.environment['OPENAI_MODEL'] ?? '';
  final input = TextEditingController(), memoryInput = TextEditingController();
  final inputFocus = FocusNode();
  final changes = ValueNotifier<int>(0);
  final motion = MotionDirector();
  final proposals = <String>[];
  TurnCancellation? cancellation;
  bool get configured => keyValue.trim().isNotEmpty && model.trim().isNotEmpty;
  bool get chosen => state?['persona'] != null;
  List<dynamic> get messages => state?['messages'] as List? ?? [];
  Map<String, dynamic>? get current {
    for (final p in profiles) {
      if (p['id'] == state?['persona']) return p as Map<String, dynamic>;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    audio = widget.audio ?? CompanionAudio();
    audio.addListener(_audioChanged);
    inputFocus.addListener(() => motion.listen(inputFocus.hasFocus));
    _open();
    stateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && !busy && !capturing && core != null)
        _run({'op': 'snapshot'});
    });
    idleTimer = Timer.periodic(const Duration(seconds: 55), (_) {
      if (mounted &&
          !busy &&
          !chatOpen &&
          panels == 0 &&
          !capturing &&
          !audio.speaking &&
          motion.motion == PetMotion.idle)
        motion.play(PetMotion.stretching, duration: const Duration(seconds: 6));
    });
  }

  void _audioChanged() {
    if (!mounted) return;
    motion.listen(capturing || inputFocus.hasFocus);
    final error = audio.error;
    if (error != lastAudioError) {
      lastAudioError = error;
      if (error != null)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _notice(error);
        });
    }
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value != AppLifecycleState.resumed) {
      _cancelVoiceCapture();
      unawaited(audio.stopSpeech());
      if (cancellation != null && progress == '正在听清你说的话')
        cancellation?.cancel();
    }
    if (value == AppLifecycleState.resumed && !busy && core != null)
      _run({'op': 'snapshot'});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    audio.removeListener(_audioChanged);
    if (widget.audio == null) audio.dispose();
    cancellation?.cancel();
    idleTimer?.cancel();
    stateTimer?.cancel();
    wakeSignal.dispose();
    devicePreferences?.dispose();
    panelResizeTimer?.cancel();
    motion.dispose();
    inputFocus.dispose();
    input.dispose();
    memoryInput.dispose();
    changes.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
      changes.value++;
    }
  }

  Future<void> _open() async {
    try {
      core = widget.core ?? await NativeCore.create();
      if (!mounted) return;
      if (core case final NativeCore native) {
        await audio.loadPreferences(
          File('${File(native.databasePath).parent.path}/audio.json'),
        );
      }
      if (core case final NativeCore native) {
        if (!mounted) return;
        final preferences = DevicePreferences(File(native.databasePath).parent);
        await preferences.load();
        if (!mounted) {
          preferences.dispose();
          return;
        }
        devicePreferences = preferences;
      } else {
        devicePreferences = DevicePreferences(
          Directory('${Directory.systemTemp.path}/alice-device-preview'),
        );
      }
      final result = await core!.call({'op': 'snapshot'});
      if (!mounted) return;
      state = result['state'];
      profiles = result['profiles'];
      startupError = null;
      _refresh();
      if (sleeping)
        motion.sleep(true);
      else
        motion.play(PetMotion.greeting);
    } catch (e) {
      if (mounted) {
        startupError = _error(e);
        _refresh();
      }
    }
  }

  String _error(Object e) => e.toString().replaceFirst('Bad state: ', '');
  void _notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<bool> _run(Map<String, dynamic> request) async {
    if (busy || core == null) return false;
    busy = true;
    _refresh();
    try {
      final result = await core!.call(request);
      if (!mounted) return false;
      state = result['state'];
      if (state!.containsKey('sleeping')) motion.sleep(sleeping);
      if (result['profiles'] != null) profiles = result['profiles'];
      if (request['op'] == 'select_persona' ||
          request['op'] == 'forget' ||
          request['op'] == 'clear_chat')
        proposals.clear();
      if (result['game_result'] != null) _notice(result['game_result']);
      _refresh();
      return true;
    } catch (e) {
      _notice(_error(e));
      return false;
    } finally {
      if (mounted) {
        busy = false;
        _refresh();
      }
    }
  }

  Future<void> _action(String action, PetMotion animation) async {
    if (!chosen) {
      await _personas();
      return;
    }
    inputFocus.unfocus();
    if (await _run({'op': 'action', 'action': action})) {
      localLine = null;
      if (animation == PetMotion.sleeping) {
        motion.sleep(true);
        localLine = '那就一起歇一会儿。醒来时，我还在这里。';
      } else {
        motion.play(animation, duration: const Duration(seconds: 5));
      }
      _refresh();
    }
  }

  Future<void> _pet() async {
    if (busy) return;
    if (!chosen) {
      _personas();
      return;
    }
    if (!await _wakePet() || !mounted) return;
    localLine = switch (state!['persona']) {
      'clever_playful' => '捕获一只摸鱼的小鲸鱼。是我呀。',
      'reserved_attentive' => '嗯……再待一会儿吧。',
      _ => '收到你的摸摸啦。也记得照顾好自己。',
    };
    motion.play(PetMotion.happy);
    _refresh();
  }

  Future<void> _chat() async {
    if (!chosen) {
      _personas();
      return;
    }
    if (!await _wakePet() || !mounted) return;
    motion.sleep(false);
    localLine = '嗯，我在。今天想和我聊些什么？';
    chatOpen = true;
    if (widget.desktop) DesktopHost.expanded(true);
    _refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) inputFocus.requestFocus();
    });
  }

  Future<void> _send() async {
    final text = input.text.trim();
    if (busy || capturing || text.isEmpty || core == null || !chosen) return;
    if (!configured) {
      await _settings();
      return;
    }
    await audio.stopSpeech();
    if (!mounted) return;
    inputFocus.unfocus();
    busy = true;
    localLine = null;
    final token = TurnCancellation();
    cancellation = token;
    motion.think(true);
    _refresh();
    try {
      final result = await (widget.agent ?? CompanionAgent()).run(
        core: core!,
        text: text,
        key: keyValue.trim(),
        model: model.trim(),
        cancellation: token,
        onProgress: (value) {
          if (mounted) {
            progress = value;
            _refresh();
          }
        },
      );
      if (!mounted) return;
      state = result.state;
      input.clear();
      proposals.addAll(
        result.memoryProposals.where((s) => !proposals.contains(s)),
      );
      if (result.animation != null)
        motion.play(PetMotion.values.byName(result.animation!));
      if (audio.autoSpeak) {
        final replies = messages.where((m) => m['role'] == 'assistant');
        if (replies.isNotEmpty) {
          final text = replies.last['content'] as String;
          if (text.runes.length <= 1200) {
            unawaited(audio.say(text, keyValue.trim()));
          } else {
            _notice('这条回复比较长，先阅读文字吧；自动朗读限 1200 字。');
          }
        }
      }
    } catch (e) {
      _notice(_error(e));
    } finally {
      if (mounted) {
        busy = false;
        cancellation = null;
        progress = '';
        motion.think(false);
        _refresh();
      }
    }
  }

  Future<void> _beginVoice() async {
    if (busy || capturing) return;
    if (!chosen) {
      await _personas();
      return;
    }
    if (!configured) {
      await _settings();
      return;
    }
    if (input.text.trim().isNotEmpty) {
      _notice('输入框里还有草稿，先发送或清空，再说话吧。');
      return;
    }
    if (!await _wakePet() || !mounted) return;
    motion.sleep(false);
    inputFocus.unfocus();
    voiceGestureEpoch++;
    await audio.beginCapture();
  }

  void _cancelVoiceCapture() {
    voiceGestureEpoch++;
    unawaited(audio.cancelCapture());
  }

  Future<void> _endVoice() async {
    final epoch = voiceGestureEpoch;
    final wav = await audio.endCapture();
    if (wav == null || !mounted || busy || epoch != voiceGestureEpoch) return;
    busy = true;
    progress = '正在听清你说的话';
    final token = TurnCancellation();
    cancellation = token;
    _refresh();
    String? transcript;
    try {
      transcript = await audio.api.transcribe(
        wav,
        key: keyValue.trim(),
        cancellation: token,
      );
      if (!mounted || token.cancelled) return;
      input.text = transcript;
      chatOpen = true;
      if (widget.desktop) await DesktopHost.expanded(true);
    } catch (e) {
      if (mounted && !token.cancelled) _notice(_error(e));
    } finally {
      if (mounted) {
        busy = false;
        progress = '';
        cancellation = null;
        _refresh();
      }
    }
    if (mounted && !token.cancelled && transcript != null) await _send();
  }

  Widget _voiceButton() => HoldToSpeak(
    key: const ValueKey('hold-to-speak'),
    enabled: !busy,
    active: capturing,
    stopping:
        audio.speaking || audio.generating || (busy && cancellation != null),
    onStart: () => unawaited(_beginVoice()),
    onEnd: () => unawaited(_endVoice()),
    onCancel: _cancelVoiceCapture,
    onStop: () {
      cancellation?.cancel();
      unawaited(audio.stopSpeech());
    },
  );

  Future<void> _sounds() => _panel(
    '声音小窝',
    (ctx) => SoundPanel(
      audio: audio,
      onPreview: () {
        if (keyValue.trim().isEmpty) {
          _notice('先在连接 OpenAI 中填写 Key，再来试听。');
          return;
        }
        unawaited(
          audio.say('嘿，我是 Alice。把今天的小烦恼放一放吧，我陪你听一会儿音乐。', keyValue.trim()),
        );
      },
      onConnect: () {
        Navigator.pop(ctx);
        unawaited(_settings());
      },
    ),
  );

  Future<void> _enterPanel() async {
    panelResizeTimer?.cancel();
    panels++;
    _refresh();
    if (widget.desktop) await DesktopHost.expanded(true);
  }

  void _leavePanel() {
    panels = math.max(0, panels - 1);
    _refresh();
    panelResizeTimer?.cancel();
    if (!mounted || !widget.desktop || panels != 0 || chatOpen) return;
    // Let the route finish closing before resizing, but cancel on disposal
    // or when another panel opens during this transition.
    panelResizeTimer = Timer(const Duration(milliseconds: 220), () {
      if (mounted && panels == 0 && !chatOpen) DesktopHost.expanded(false);
    });
  }

  Future<void> _panel(
    String title,
    Widget Function(BuildContext) content,
  ) async {
    inputFocus.unfocus();
    await _enterPanel();
    if (!mounted) return;
    Widget body(BuildContext ctx) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          20 + MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(
              120,
              MediaQuery.sizeOf(ctx).height * .8 -
                  MediaQuery.viewInsetsOf(ctx).bottom,
            ),
          ),
          child: ValueListenableBuilder<int>(
            valueListenable: changes,
            builder: (_, value, child) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('close-panel'),
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(child: SingleChildScrollView(child: content(ctx))),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      if (widget.desktop) {
        await showDialog<void>(
          context: context,
          barrierColor: Colors.transparent,
          builder: (ctx) => Dialog(
            backgroundColor: paper,
            insetPadding: const EdgeInsets.all(12),
            child: SizedBox(width: 480, child: body(ctx)),
          ),
        );
      } else {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          backgroundColor: paper,
          constraints: const BoxConstraints(maxWidth: 520),
          builder: body,
        );
      }
    } finally {
      _leavePanel();
    }
  }

  Future<void> _arcade(ArcadeKind kind) async {
    await _enterPanel();
    if (!mounted) return;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: widget.desktop ? Colors.transparent : Colors.black26,
        builder: (ctx) => Dialog(
          backgroundColor: paper,
          insetPadding: const EdgeInsets.all(10),
          child: SizedBox(
            width: 480,
            height: math.min(740, MediaQuery.sizeOf(ctx).height - 40),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ArcadeRoom(
                kind: kind,
                best:
                    ((state?['arcade'] as Map?)?[kind.name]?['best'] as num?)
                        ?.toInt() ??
                    0,
                onResult: (runId, score) async {
                  final result = await core!.call({
                    'op': 'arcade_result',
                    'game': kind.name,
                    'run_id': runId,
                    'score': score,
                  });
                  if (mounted) {
                    state = result['state'];
                    motion.play(PetMotion.happy);
                    _refresh();
                  }
                },
              ),
            ),
          ),
        ),
      );
    } finally {
      _leavePanel();
    }
  }

  Future<void> _personas() => _panel(
    '想怎样和我相处？',
    (ctx) => Column(
      children: [
        const Text(
          '还是同一个 Alice，只是表达心意的方式不同。',
          style: TextStyle(color: muted, height: 1.7),
        ),
        const SizedBox(height: 18),
        for (final p in profiles)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: state?['persona'] == p['id']
                  ? const Color(0xFFECECF8)
                  : Colors.white,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                key: ValueKey<String>(p['id'] as String),
                borderRadius: BorderRadius.circular(22),
                onTap: busy
                    ? null
                    : () async {
                        if (await _run({
                          'op': 'select_persona',
                          'id': p['id'],
                        })) {
                          if (!mounted || !ctx.mounted) return;
                          localLine = null;
                          motion.play(PetMotion.greeting);
                          Navigator.pop(ctx);
                          _refresh();
                        }
                      },
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p['card']['title'],
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            state?['persona'] == p['id']
                                ? Icons.check_circle_rounded
                                : Icons.favorite_border_rounded,
                            size: 20,
                            color: accent,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        p['card']['preview'],
                        style: const TextStyle(color: muted, height: 1.7),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
  Future<void> _settings() async {
    inputFocus.unfocus();
    await _enterPanel();
    if (!mounted) return;
    final saved = await showDialog<ConnectionSettings>(
      context: context,
      builder: (_) =>
          ConnectionDialog(initialKey: keyValue, initialModel: model),
    );
    _leavePanel();
    if (saved != null && mounted) {
      keyValue = saved.key;
      model = saved.model;
      _refresh();
    }
  }

  Future<void> _memory() => _panel(
    '我们的记忆',
    (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('只记住你愿意留下的事。', style: TextStyle(color: muted)),
        if (proposals.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text(
            'Alice 想确认',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          for (final proposal in proposals.toList())
            Card(
              elevation: 0,
              color: const Color(0xFFEFEDF8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(proposal),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: busy
                              ? null
                              : () {
                                  proposals.remove(proposal);
                                  _refresh();
                                },
                          child: const Text('不用记'),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  if (await _run({
                                    'op': 'remember',
                                    'content': proposal,
                                  })) {
                                    proposals.remove(proposal);
                                    _refresh();
                                  }
                                },
                          child: const Text('确认记住'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 18),
        TextField(
          key: const ValueKey('memory-input'),
          controller: memoryInput,
          maxLength: 600,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '比如：我喜欢下雨天，也喜欢热可可'),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: busy
                ? null
                : () async {
                    if (await _run({
                      'op': 'remember',
                      'content': memoryInput.text,
                    })) {
                      memoryInput.clear();
                      _refresh();
                    }
                  },
            child: const Text('记住这件事'),
          ),
        ),
        for (final m in (state?['memories'] as List? ?? []).reversed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bookmark_border_rounded, color: accent),
            title: Text(m['content'], style: const TextStyle(fontSize: 14)),
            trailing: IconButton(
              tooltip: '忘记这件事',
              onPressed: busy
                  ? null
                  : () => _run({'op': 'forget', 'id': m['id']}),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ),
        if ((state?['memories'] as List? ?? []).isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              '记忆的小本子还空着，慢慢写就好。',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
          ),
      ],
    ),
  );
  Future<void> _history() => _panel(
    '说过的话',
    (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (messages.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('故事从下一句话开始。', textAlign: TextAlign.center),
          ),
        for (final m in messages.reversed)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: m['role'] == 'user'
                  ? const Color(0xFFEDECF7)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m['role'] == 'user'
                      ? '你'
                      : m['mode'] == 'online'
                      ? 'Alice'
                      : 'Alice · 本地互动',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  m['content'],
                  style: const TextStyle(height: 1.8),
                ),
              ],
            ),
          ),
        if (messages.isNotEmpty)
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('清空聊天记录？'),
                        content: const Text('会清空本地聊天和对话摘录，已确认的长期记忆仍然保留。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('保留'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('清空'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) {
                      await _run({'op': 'clear_chat'});
                      localLine = null;
                      _refresh();
                    }
                  },
            child: const Text('清空聊天记录'),
          ),
      ],
    ),
  );
  Future<void> _game() => _panel(
    '珍珠躲在哪里？',
    (ctx) => Column(
      children: [
        const Text('猜一猜，哪只贝壳藏着小珍珠？', style: TextStyle(color: muted)),
        const SizedBox(height: 22),
        if (state?['game'] == 'playing')
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < 3; i++)
                FilledButton.tonal(
                  onPressed: busy
                      ? null
                      : () async {
                          if (await _run({
                            'op': 'action',
                            'action': 'guess',
                            'guess': i,
                          })) {
                            localLine = null;
                            motion.play(PetMotion.happy);
                            _refresh();
                          }
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
            ],
          )
        else
          FilledButton.tonal(
            onPressed: busy
                ? null
                : () => _run({'op': 'action', 'action': 'start_game'}),
            child: const Text('藏好珍珠'),
          ),
        const SizedBox(height: 20),
      ],
    ),
  );
  Future<void> _more() => _panel(
    '小小抽屉',
    (ctx) => Column(
      children: [
        _menu(ctx, Icons.auto_stories_outlined, '说过的话', _history),
        _menu(
          ctx,
          Icons.bookmark_border_rounded,
          proposals.isEmpty ? '我们的记忆' : '我们的记忆 · 有待确认',
          _memory,
        ),
        _menu(ctx, Icons.favorite_border_rounded, '相处方式', _personas),
        if (chosen) ...[
          _menu(ctx, Icons.spa_outlined, '照顾她', _care),
          _menu(ctx, Icons.bubble_chart_outlined, '找珍珠', _game),
          _menu(
            ctx,
            Icons.grid_view_rounded,
            '俄罗斯方块',
            () => _arcade(ArcadeKind.tetris),
          ),
          _menu(
            ctx,
            Icons.sports_tennis_rounded,
            '打砖块',
            () => _arcade(ArcadeKind.breakout),
          ),
        ],
        if (widget.desktop) ...[
          SwitchListTile(
            title: const Text('置顶陪伴'),
            value: onTop,
            onChanged: (v) {
              onTop = v;
              DesktopHost.onTop(v);
              _refresh();
            },
          ),
          _menu(ctx, Icons.close_rounded, '退出 Alice', () async {
            cancellation?.cancel();
            await audio.shutdown();
            await DesktopHost.close();
          }),
        ],
        _menu(ctx, Icons.headphones_rounded, '声音小窝 · lo-fi 与语音', _sounds),
        _menu(ctx, Icons.self_improvement_rounded, '伸个懒腰', () async {
          if (!await _wakePet() || !mounted) return;
          motion.play(
            PetMotion.stretching,
            duration: const Duration(seconds: 6),
          );
        }),
        if (devicePreferences != null)
          _menu(ctx, Icons.wallpaper_rounded, '待机与欢迎', _deviceSettings),
        if (widget.deviceMode && Platform.isLinux)
          _menu(ctx, Icons.wifi_rounded, '连接 Wi-Fi', _wifi),
        if (widget.deviceMode)
          _menu(ctx, Icons.close_rounded, '退出 Alice', () async {
            await audio.shutdown();
            await DesktopHost.close();
          }),
        _menu(ctx, Icons.tune_rounded, '连接 OpenAI', _settings),
      ],
    ),
  );
  Widget _menu(
    BuildContext ctx,
    IconData icon,
    String label,
    Future<void> Function() open,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    leading: Icon(icon, color: accent),
    title: Text(label),
    trailing: const Icon(Icons.chevron_right_rounded, color: muted),
    onTap: () async {
      Navigator.pop(ctx);
      await Future<void>.delayed(const Duration(milliseconds: 280));
      if (mounted) await open();
    },
  );
  String get bubble {
    if (audio.status.isNotEmpty) return audio.status;
    if (busy && cancellation != null) return '$progress…';
    if (localLine != null) return localLine!;
    if (!chosen) return '你好呀，我是 Alice。\n想在你的日常里，留一小片海。';
    final replies = messages.where((m) => m['role'] == 'assistant');
    return replies.isEmpty ? '我在这里。慢慢说，或者一起发会儿呆。' : replies.last['content'];
  }

  @override
  Widget build(BuildContext context) =>
      widget.deviceMode && devicePreferences != null
      ? _device()
      : widget.desktop
      ? _desktop()
      : Scaffold(
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFF7F5FD),
                  Color(0xFFFCFAF8),
                  Color(0xFFF1F5FA),
                ],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: SizedBox(
                        height: math.max(
                          constraints.maxHeight,
                          chatOpen ? 560 : 500,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFB4B8D8),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  const Text(
                                    'Alice',
                                    style: TextStyle(
                                      fontSize: 19,
                                      letterSpacing: 1.1,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    key: const ValueKey('more'),
                                    tooltip: '小小抽屉',
                                    onPressed: busy ? null : _more,
                                    icon: const Icon(
                                      Icons.more_horiz_rounded,
                                      color: muted,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              if (startupError != null) ...[
                                Text(
                                  startupError!,
                                  textAlign: TextAlign.center,
                                ),
                                TextButton(
                                  onPressed: _open,
                                  child: const Text('重新打开'),
                                ),
                              ] else if (state == null)
                                const LinearProgressIndicator(minHeight: 2)
                              else
                                GestureDetector(
                                  onTap: chosen && !busy ? _history : null,
                                  child: Container(
                                    key: const ValueKey('speech'),
                                    constraints: const BoxConstraints(
                                      minHeight: 84,
                                    ),
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 22,
                                      vertical: 18,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: .88,
                                      ),
                                      borderRadius: const BorderRadius.all(
                                        Radius.circular(26),
                                      ),
                                      border: Border.all(color: Colors.white),
                                      boxShadow: [
                                        BoxShadow(
                                          color: accent.withValues(alpha: .045),
                                          blurRadius: 24,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      bubble,
                                      textAlign: TextAlign.center,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        height: 1.9,
                                      ),
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: ListenableBuilder(
                                  listenable: motion,
                                  builder: (context, _) => Column(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          key: const ValueKey('pet'),
                                          onTap: busy ? null : _pet,
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              FractionallySizedBox(
                                                widthFactor: .85,
                                                heightFactor: .82,
                                                child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    gradient: RadialGradient(
                                                      colors: [
                                                        const Color(
                                                          0xFFE7E8F8,
                                                        ).withValues(alpha: .7),
                                                        const Color(
                                                          0xFFE7E8F8,
                                                        ).withValues(alpha: 0),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                bottom: 10,
                                                child: Container(
                                                  width: 150,
                                                  height: 15,
                                                  decoration: BoxDecoration(
                                                    color: accent.withValues(
                                                      alpha: .08,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          100,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              Positioned.fill(
                                                child: PetCharacter(
                                                  motion: motion.motion,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      Text(
                                        motion.motion.label,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: muted,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              if (state != null && !chosen)
                                FilledButton.tonal(
                                  onPressed: _personas,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 6,
                                    ),
                                    child: Text('选择她的性格'),
                                  ),
                                )
                              else if (chosen) ...[
                                if (chatOpen)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            key: const ValueKey('chat-input'),
                                            controller: input,
                                            focusNode: inputFocus,
                                            readOnly: busy || capturing,
                                            minLines: 1,
                                            maxLines: 3,
                                            maxLength: 4000,
                                            textInputAction:
                                                TextInputAction.send,
                                            onSubmitted: (_) => _send(),
                                            decoration: const InputDecoration(
                                              hintText: '想说的话，慢慢说…',
                                              counterText: '',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        _voiceButton(),
                                        IconButton.filledTonal(
                                          key: const ValueKey('send'),
                                          tooltip: busy ? '停止回复' : '发送',
                                          onPressed: busy
                                              ? () => cancellation?.cancel()
                                              : _send,
                                          icon: Icon(
                                            busy
                                                ? Icons.stop_rounded
                                                : Icons.arrow_upward_rounded,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: '收起聊天',
                                          onPressed: busy
                                              ? null
                                              : () {
                                                  inputFocus.unfocus();
                                                  chatOpen = false;
                                                  _refresh();
                                                },
                                          icon: const Icon(
                                            Icons.keyboard_arrow_down_rounded,
                                            color: muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _dock(
                                      Icons.chat_bubble_outline_rounded,
                                      '聊聊',
                                      _chat,
                                    ),
                                    _dock(
                                      Icons.favorite_border_rounded,
                                      '摸摸',
                                      _pet,
                                    ),
                                    _dock(
                                      Icons.local_cafe_outlined,
                                      '喝茶',
                                      () => _action('tea', PetMotion.tea),
                                    ),
                                    ListenableBuilder(
                                      listenable: motion,
                                      builder: (_, child) => _dock(
                                        motion.sleeping
                                            ? Icons.wb_sunny_outlined
                                            : Icons.nightlight_outlined,
                                        motion.sleeping ? '醒来' : '休息',
                                        () {
                                          _rest();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 12),
                              if (proposals.isNotEmpty)
                                TextButton(
                                  onPressed: busy ? null : _memory,
                                  child: const Text('有件事，想问问你能不能记住'),
                                )
                              else
                                Text(
                                  configured
                                      ? '小小鲸屿 · 有你在就好'
                                      : '离线陪伴 · 也可以一起发呆',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: muted,
                                    letterSpacing: .7,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
  void _closeChat() {
    inputFocus.unfocus();
    chatOpen = false;
    if (widget.desktop && panels == 0) DesktopHost.expanded(false);
    _refresh();
  }

  Future<void> _rest() async {
    if (sleeping || motion.sleeping) {
      if (await _wakePet()) {
        motion.sleep(false);
        motion.play(PetMotion.greeting);
        localLine = '醒啦。我们继续慢慢来。';
        _refresh();
      }
    } else {
      await _action('rest', PetMotion.sleeping);
    }
  }

  Future<void> _deviceSettings() => _panel(
    '待机与欢迎',
    (ctx) => DeviceSettingsPanel(
      preferences: devicePreferences!,
      onSaved: () {
        Navigator.pop(ctx);
        wakeSignal.value++;
      },
    ),
  );
  Future<void> _wifi() => _panel('连接 Wi-Fi', (_) => const WifiPanel());
  Future<void> _care() => _panel(
    '照顾她',
    (ctx) => Column(
      children: [
        const Text('吃饱、洗香香，再睡个好觉。', style: TextStyle(color: muted)),
        const SizedBox(height: 20),
        for (final item in [
          ('饱腹', 'satiety'),
          ('清洁', 'cleanliness'),
          ('精力', 'energy'),
          ('舒适', 'comfort'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                SizedBox(width: 50, child: Text(item.$1)),
                Expanded(
                  child: LinearProgressIndicator(
                    value: ((state?[item.$2] as num?)?.toDouble() ?? 70) / 100,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                SizedBox(
                  width: 38,
                  child: Text(
                    '${((state?[item.$2] as num?) ?? 70).round()}',
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('care-feed'),
              onPressed: busy || sleeping
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await _action('feed', PetMotion.feeding);
                    },
              icon: const Icon(Icons.bakery_dining_rounded),
              label: const Text('喂点心'),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('care-bath'),
              onPressed: busy || sleeping
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await _action('bath', PetMotion.bathing);
                    },
              icon: const Icon(Icons.bubble_chart_outlined),
              label: const Text('洗泡泡澡'),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('care-sleep'),
              onPressed: busy
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await _rest();
                    },
              icon: Icon(
                sleeping ? Icons.wb_sunny_outlined : Icons.bedtime_outlined,
              ),
              label: Text(sleeping ? '轻轻叫醒' : '盖好被子'),
            ),
          ],
        ),
        if (sleeping)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('她正在休息，睡醒后再吃点心和洗澡。'),
          ),
      ],
    ),
  );

  Widget _device() => ListenableBuilder(
    listenable: motion,
    builder: (context, _) => DeviceRoom(
      preferences: devicePreferences!,
      motion: motion.motion,
      bubble: startupError ?? bubble,
      chosen: chosen,
      occupied:
          busy ||
          chatOpen ||
          panels > 0 ||
          capturing ||
          audio.speaking ||
          audio.generating,
      wakeSignal: wakeSignal,
      onPet: _pet,
      onMore: _more,
      onChoose: _personas,
      composer: chatOpen
          ? Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('chat-input'),
                    controller: input,
                    focusNode: inputFocus,
                    readOnly: busy || capturing,
                    maxLength: 4000,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: '想说的话，慢慢说…',
                      counterText: '',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  key: const ValueKey('send'),
                  tooltip: busy ? '停止回复' : '发送',
                  onPressed: busy ? () => cancellation?.cancel() : _send,
                  icon: Icon(
                    busy ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                  ),
                ),
                IconButton(
                  tooltip: '收起聊天',
                  onPressed: _closeChat,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ],
            )
          : null,
      controls: chosen
          ? Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              children: [
                _dock(Icons.chat_bubble_outline_rounded, '聊聊', _chat),
                _dock(Icons.spa_outlined, '照顾她', _care),
                _dock(Icons.headphones_rounded, '听歌', _sounds),
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: _voiceButton(),
                ),
              ],
            )
          : const SizedBox(),
    ),
  );

  Widget _desktop() => ListenableBuilder(
    listenable: motion,
    builder: (context, _) => DesktopPet(
      character: PetCharacter(motion: motion.motion),
      bubble: bubble,
      chosen: chosen,
      busy: busy || capturing || audio.speaking || audio.generating,
      error: startupError,
      onPet: _pet,
      onChat: _chat,
      onMore: _more,
      onChoose: _personas,
      controls: Wrap(
        alignment: WrapAlignment.center,
        children: [
          IconButton(
            tooltip: '聊聊',
            onPressed: busy ? null : _chat,
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 21),
          ),
          IconButton(
            tooltip: '摸摸',
            onPressed: busy ? null : _pet,
            icon: const Icon(Icons.favorite_border_rounded, size: 21),
          ),
          IconButton(
            tooltip: '喝茶',
            onPressed: busy ? null : () => _action('tea', PetMotion.tea),
            icon: const Icon(Icons.local_cafe_outlined, size: 21),
          ),
          IconButton(
            tooltip: motion.sleeping ? '醒来' : '休息',
            onPressed: busy ? null : _rest,
            icon: Icon(
              motion.sleeping
                  ? Icons.wb_sunny_outlined
                  : Icons.nightlight_outlined,
              size: 21,
            ),
          ),
          _voiceButton(),
          IconButton(
            key: const ValueKey('music-quick'),
            tooltip: audio.playing ? '暂停 lo-fi' : '播放 lo-fi',
            onPressed: audio.musicLoading ? null : audio.toggleMusic,
            icon: Icon(
              audio.playing
                  ? Icons.pause_circle_outline_rounded
                  : Icons.music_note_rounded,
              size: 21,
            ),
          ),
          IconButton(
            key: const ValueKey('more'),
            tooltip: '小小抽屉',
            onPressed: busy ? null : _more,
            icon: const Icon(Icons.more_horiz_rounded, size: 21),
          ),
        ],
      ),
      composer: chatOpen
          ? Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('chat-input'),
                    controller: input,
                    focusNode: inputFocus,
                    readOnly: busy || capturing,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 4000,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: '想说的话，慢慢说…',
                      counterText: '',
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  key: const ValueKey('send'),
                  tooltip: busy ? '停止回复' : '发送',
                  onPressed: busy ? () => cancellation?.cancel() : _send,
                  icon: Icon(
                    busy ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                  ),
                ),
                IconButton(
                  tooltip: '收起聊天',
                  onPressed: busy ? null : _closeChat,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ],
            )
          : null,
    ),
  );
  Widget _dock(IconData icon, String title, VoidCallback onTap) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton.filledTonal(
        onPressed: busy ? null : onTap,
        tooltip: title,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: .85),
          foregroundColor: accent,
          padding: const EdgeInsets.all(15),
        ),
        icon: Icon(icon, size: 22),
      ),
      const SizedBox(height: 5),
      Text(title, style: const TextStyle(fontSize: 12, color: muted)),
    ],
  );
}

class ConnectionSettings {
  final String key, model;
  const ConnectionSettings(this.key, this.model);
}

/// Controllers belong to the dialog's lifecycle, including its closing animation.
class ConnectionDialog extends StatefulWidget {
  final String initialKey, initialModel;
  const ConnectionDialog({
    super.key,
    required this.initialKey,
    required this.initialModel,
  });
  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  late final keyInput = TextEditingController(text: widget.initialKey);
  late final modelInput = TextEditingController(text: widget.initialModel);
  String? error;
  @override
  void dispose() {
    keyInput.dispose();
    modelInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('连接 OpenAI'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '填入你自己的 Key，就能和 Alice 聊天、说话。',
              style: TextStyle(color: muted, height: 1.8),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const ValueKey('api-key'),
              controller: keyInput,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'OpenAI API Key',
                hintText: 'sk-… 或 sk-proj-…',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('api-model'),
              controller: modelInput,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '聊天模型 ID',
                hintText: '填写你的账号可用的模型',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Key 仅用于本次启动，不写入存档。聊天使用 Responses 接口，发送当前人设、相关记忆和近期对话。\n\n语音会另行使用录音识别与声音生成接口；自动朗读和音色可在「声音小窝」调整。',
              style: TextStyle(fontSize: 12, color: muted, height: 1.7),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('稍后再说'),
      ),
      FilledButton.tonal(
        onPressed: () {
          final key = keyInput.text.trim(), model = modelInput.text.trim();
          if (key.isNotEmpty &&
              (key.contains(RegExp(r'\s')) ||
                  key.toLowerCase().startsWith('bearer'))) {
            setState(() => error = '粘贴 Key 本身即可，不要添加 Bearer 或空格。');
            return;
          }
          if (key.isNotEmpty && model.isEmpty) {
            setState(() => error = '还需要填写可用的模型 ID。');
            return;
          }
          Navigator.pop(context, ConnectionSettings(key, model));
        },
        child: const Text('保存设置'),
      ),
    ],
  );
}
