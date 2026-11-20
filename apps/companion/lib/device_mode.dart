import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'character_animation.dart';

class DevicePreferences extends ChangeNotifier {
  final Directory root;
  String welcome = '回来啦，给你留了一小片海。';
  int idleSeconds = 60, theme = 0;
  bool clock = true;
  String? background;
  DevicePreferences(this.root);
  Future<void> load() async {
    await root.create(recursive: true);
    final file = File('${root.path}/device.json');
    if (!await file.exists()) return;
    try {
      final data = jsonDecode(await file.readAsString()) as Map;
      if (data['welcome'] is String && (data['welcome'] as String).length <= 80)
        welcome = data['welcome'];
      if ([0, 30, 60, 180, 300].contains(data['idleSeconds']))
        idleSeconds = data['idleSeconds'];
      if ([0, 1, 2].contains(data['theme'])) theme = data['theme'];
      clock = data['clock'] != false;
      final name = data['background'];
      if (name is String &&
          RegExp(r'^background-\d+\.(png|jpg|jpeg|webp)$').hasMatch(name) &&
          await File('${root.path}/$name').exists())
        background = name;
    } catch (_) {
      /* Optional appearance preferences cannot block the pet. */
    }
    notifyListeners();
  }

  Future<void> save({
    required String text,
    required int idle,
    required int color,
    required bool showClock,
    String? image,
  }) async {
    final value = text.trim();
    if (value.isEmpty || value.length > 80)
      throw StateError('欢迎语写 1 到 80 个字就好。');
    if (![0, 30, 60, 180, 300].contains(idle) || ![0, 1, 2].contains(color))
      throw StateError('请选择有效的待机设置。');
    final file = File('${root.path}/device.json.tmp');
    await file.writeAsString(
      jsonEncode({
        'welcome': value,
        'idleSeconds': idle,
        'theme': color,
        'clock': showClock,
        'background': image,
      }),
      flush: true,
    );
    await file.rename('${root.path}/device.json');
    final previous = background;
    welcome = value;
    idleSeconds = idle;
    theme = color;
    clock = showClock;
    background = image;
    notifyListeners();
    if (previous != null && previous != image) {
      try {
        await File('${root.path}/$previous').delete();
      } catch (_) {
        /* Best effort old wallpaper cleanup. */
      }
    }
  }

  Future<String> importBackground(XFile source) async {
    final ext = source.name.split('.').last.toLowerCase();
    if (!['png', 'jpg', 'jpeg', 'webp'].contains(ext) ||
        await source.length() > 12 * 1024 * 1024)
      throw StateError('请选择不超过 12 MB 的 PNG、JPG 或 WebP 图片。');
    final bytes = await source.readAsBytes();
    if (bytes.length > 12 * 1024 * 1024) throw StateError('图片超过了 12 MB。');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width > 4096 || descriptor.height > 4096)
          throw StateError('图片最长边请控制在 4096 像素以内。');
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
    final name = 'background-${DateTime.now().microsecondsSinceEpoch}.$ext';
    await File('${root.path}/$name').writeAsBytes(bytes, flush: true);
    return name;
  }
}

class DeviceSettingsPanel extends StatefulWidget {
  final DevicePreferences preferences;
  final VoidCallback onSaved;
  const DeviceSettingsPanel({
    super.key,
    required this.preferences,
    required this.onSaved,
  });
  @override
  State<DeviceSettingsPanel> createState() => _DeviceSettingsPanelState();
}

class _DeviceSettingsPanelState extends State<DeviceSettingsPanel> {
  late final text = TextEditingController(text: widget.preferences.welcome);
  late int idle = widget.preferences.idleSeconds,
      theme = widget.preferences.theme;
  late bool clock = widget.preferences.clock;
  late String? image = widget.preferences.background;
  final temporaryImages = <String>[];
  bool working = false;
  String? error;
  @override
  void dispose() {
    text.dispose();
    for (final name in temporaryImages) {
      if (name != widget.preferences.background) {
        unawaited(
          File(
            '${widget.preferences.root.path}/$name',
          ).delete().then<void>((_) {}, onError: (Object _) {}),
        );
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        key: const ValueKey('welcome-text'),
        controller: text,
        maxLength: 80,
        decoration: const InputDecoration(labelText: '见面时说的话'),
      ),
      DropdownButtonFormField<int>(
        initialValue: idle,
        decoration: const InputDecoration(labelText: '多久后进入待机'),
        items: [
          for (final n in [0, 30, 60, 180, 300])
            DropdownMenuItem(value: n, child: Text(n == 0 ? '保持陪伴画面' : '$n 秒')),
        ],
        onChanged: working ? null : (n) => setState(() => idle = n!),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        children: [
          for (var i = 0; i < 3; i++)
            ChoiceChip(
              label: Text(['小片海', '桃子汽水', '月亮晚安'][i]),
              selected: theme == i,
              onSelected: working ? null : (_) => setState(() => theme = i),
            ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('待机时显示时钟'),
        value: clock,
        onChanged: working ? null : (v) => setState(() => clock = v),
      ),
      if (image != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(
            File('${widget.preferences.root.path}/$image'),
            height: 120,
            fit: BoxFit.cover,
            errorBuilder: (_, e, s) => const Text('这张背景暂时无法显示'),
          ),
        ),
      TextButton.icon(
        onPressed: working
            ? null
            : () async {
                setState(() {
                  working = true;
                  error = null;
                });
                try {
                  final file = await openFile(
                    acceptedTypeGroups: const [
                      XTypeGroup(
                        label: '背景图片',
                        extensions: ['png', 'jpg', 'jpeg', 'webp'],
                        uniformTypeIdentifiers: ['public.image'],
                      ),
                    ],
                  );
                  if (file != null) {
                    final name = await widget.preferences.importBackground(
                      file,
                    );
                    if (!mounted) {
                      await File(
                        '${widget.preferences.root.path}/$name',
                      ).delete();
                      return;
                    }
                    temporaryImages.add(name);
                    image = name;
                  }
                } catch (e) {
                  if (mounted)
                    error = e is StateError
                        ? e.message.toString()
                        : '这张图片没能导入，请换一张试试。';
                } finally {
                  if (mounted) setState(() => working = false);
                }
              },
        icon: const Icon(Icons.wallpaper_rounded),
        label: const Text('选择自己的背景'),
      ),
      if (image != null)
        TextButton(
          onPressed: working ? null : () => setState(() => image = null),
          child: const Text('使用主题背景'),
        ),
      if (error != null)
        Text(error!, style: const TextStyle(color: Colors.redAccent)),
      FilledButton.tonal(
        onPressed: working
            ? null
            : () async {
                setState(() {
                  working = true;
                  error = null;
                });
                try {
                  await widget.preferences.save(
                    text: text.text,
                    idle: idle,
                    color: theme,
                    showClock: clock,
                    image: image,
                  );
                  if (mounted) widget.onSaved();
                } catch (_) {
                  if (mounted)
                    setState(() {
                      working = false;
                      error = '设置没能保存，请检查文字和存储空间。';
                    });
                }
              },
        child: const Text('就这样，保存'),
      ),
    ],
  );
}

/// The display may rest while the local core and audio keep running. This is
/// an application screen, not a claim of hardware suspend or backlight control.
class DeviceRoom extends StatefulWidget {
  final DevicePreferences preferences;
  final PetMotion motion;
  final String bubble;
  final bool chosen, occupied;
  final Widget controls;
  final Widget? composer;
  final VoidCallback onPet, onMore, onChoose;
  final ValueNotifier<int> wakeSignal;
  const DeviceRoom({
    super.key,
    required this.preferences,
    required this.motion,
    required this.bubble,
    required this.chosen,
    required this.occupied,
    required this.controls,
    required this.onPet,
    required this.onMore,
    required this.onChoose,
    required this.wakeSignal,
    this.composer,
  });
  @override
  State<DeviceRoom> createState() => _DeviceRoomState();
}

class _DeviceRoomState extends State<DeviceRoom> {
  Timer? timer;
  int idleTicks = 0;
  bool standby = false, welcome = true;
  DateTime time = DateTime.now();
  @override
  void initState() {
    super.initState();
    widget.wakeSignal.addListener(_wake);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        time = DateTime.now();
        idleTicks++;
        if (widget.occupied || !widget.chosen) idleTicks = 0;
        if (idleTicks >= 5) welcome = false;
        if (!widget.occupied &&
            widget.chosen &&
            widget.preferences.idleSeconds > 0 &&
            idleTicks >= widget.preferences.idleSeconds)
          standby = true;
      });
    });
  }

  void _wake() {
    if (mounted)
      setState(() {
        standby = false;
        welcome = true;
        idleTicks = 0;
      });
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.wakeSignal.removeListener(_wake);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.preferences,
    builder: (context, _) {
      final p = widget.preferences;
      final colors = [
        const [Color(0xFFEAF5FA), Color(0xFFFAF8F4)],
        const [Color(0xFFFFE7E4), Color(0xFFFFF7EC)],
        const [Color(0xFFDBDDF2), Color(0xFFF2EBF8)],
      ][p.theme];
      return Scaffold(
        key: const ValueKey('device-room'),
        body: Listener(
          onPointerDown: (_) {
            idleTicks = 0;
            if (!standby) welcome = false;
          },
          onPointerMove: (_) => idleTicks = 0,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: colors,
                  ),
                ),
              ),
              if (p.background != null)
                Opacity(
                  opacity: .45,
                  child: Image.file(
                    File('${p.root.path}/${p.background}'),
                    fit: BoxFit.cover,
                    cacheWidth: 1280,
                    errorBuilder: (_, e, s) => const SizedBox(),
                  ),
                ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, size) => SingleChildScrollView(
                    child: SizedBox(
                      height: size.maxHeight.clamp(520, double.infinity),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Alice',
                                  style: TextStyle(
                                    fontSize: 16,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const Spacer(),
                                if (!standby)
                                  IconButton(
                                    key: const ValueKey('device-more'),
                                    tooltip: '小小抽屉',
                                    onPressed: widget.onMore,
                                    icon: const Icon(Icons.more_horiz_rounded),
                                  ),
                              ],
                            ),
                            if (standby && p.clock)
                              Padding(
                                padding: const EdgeInsets.only(top: 20),
                                child: Text(
                                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                standby
                                    ? '我在这里，陪你慢慢过今天。'
                                    : welcome && widget.chosen
                                    ? p.welcome
                                    : widget.bubble,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.8,
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                key: const ValueKey('device-pet'),
                                onTap: standby ? _wake : widget.onPet,
                                child: TickerMode(
                                  enabled: !standby,
                                  child: PetCharacter(motion: widget.motion),
                                ),
                              ),
                            ),
                            if (!widget.chosen)
                              FilledButton.tonal(
                                onPressed: widget.onChoose,
                                child: const Text('选择她的性格'),
                              ),
                            if (standby)
                              const Padding(
                                padding: EdgeInsets.all(20),
                                child: Text(
                                  '轻轻碰一下，叫我回来',
                                  style: TextStyle(fontSize: 12),
                                ),
                              )
                            else ...[
                              if (widget.composer != null) widget.composer!,
                              const SizedBox(height: 12),
                              widget.controls,
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (standby)
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('standby-wake'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _wake,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: .12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
