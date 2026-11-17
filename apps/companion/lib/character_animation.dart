import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum PetMotion { idle, greeting, listening, thinking, happy, tea, sleeping }

extension MotionSpec on PetMotion {
  String get label => switch (this) {
    PetMotion.idle => '陪在你身边',
    PetMotion.greeting => '见到你很开心',
    PetMotion.listening => '我在听',
    PetMotion.thinking => '让我想一想',
    PetMotion.happy => '蹭蹭你的手',
    PetMotion.tea => '一起喝杯茶',
    PetMotion.sleeping => '小憩一会儿',
  };
  String get sheet => switch (this) {
    PetMotion.idle || PetMotion.listening => 'calm',
    PetMotion.greeting || PetMotion.happy => 'social',
    _ => 'activities',
  };
  int get row => switch (this) {
    PetMotion.listening || PetMotion.happy || PetMotion.tea => 1,
    PetMotion.sleeping => 2,
    _ => 0,
  };
  List<int> get timing => switch (this) {
    PetMotion.idle => [2800, 100, 130, 180],
    PetMotion.listening => [1300, 650, 140, 700],
    PetMotion.thinking => [900, 650, 140, 800],
    PetMotion.greeting => [320, 240, 240, 320],
    PetMotion.happy => [350, 300, 350, 450],
    PetMotion.tea => [900, 650, 1600, 850],
    PetMotion.sleeping => [1100, 1100, 1100, 1100],
  };
  int frameAt(int elapsedMs) {
    final durations = timing;
    var t = elapsedMs % durations.reduce((a, b) => a + b);
    for (var i = 0; i < durations.length; i++) {
      if (t < durations[i]) return i;
      t -= durations[i];
    }
    return 0;
  }
}

/// One owner for scene priority. Old transient timers cannot override a chat turn.
class MotionDirector extends ChangeNotifier {
  bool thinking = false, listening = false, sleeping = false;
  PetMotion? transient;
  Timer? _timer;
  PetMotion get motion => thinking
      ? PetMotion.thinking
      : sleeping
      ? PetMotion.sleeping
      : transient ?? (listening ? PetMotion.listening : PetMotion.idle);
  void think(bool value) {
    thinking = value;
    if (value) {
      sleeping = false;
      transient = null;
      _timer?.cancel();
    }
    notifyListeners();
  }

  void listen(bool value) {
    listening = value;
    notifyListeners();
  }

  void sleep(bool value) {
    sleeping = value;
    transient = null;
    _timer?.cancel();
    notifyListeners();
  }

  void play(PetMotion value, {Duration duration = const Duration(seconds: 3)}) {
    _timer?.cancel();
    sleeping = false;
    transient = value;
    notifyListeners();
    _timer = Timer(duration, () {
      transient = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Three shared decoded sheets. No image decoding in the animation loop.
class _Sheets {
  static final Map<String, Future<ui.Image>> images = {};
  static Future<ui.Image> load(String name) =>
      images.putIfAbsent(name, () async {
        final data = await rootBundle.load('assets/animations/$name.png');
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      });
}

class PetCharacter extends StatefulWidget {
  final PetMotion motion;
  const PetCharacter({super.key, required this.motion});
  @override
  State<PetCharacter> createState() => _PetCharacterState();
}

class _PetCharacterState extends State<PetCharacter>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController clock;
  final Map<String, ui.Image> sheets = {};
  bool active = true, reduce = false, failed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    );
    for (final name in ['calm', 'social', 'activities']) {
      _Sheets.load(name)
          .then((image) {
            if (mounted) setState(() => sheets[name] = image);
          })
          .catchError((Object _) {
            if (mounted) setState(() => failed = true);
          });
    }
  }

  void _sync() {
    if (active && !reduce && TickerMode.valuesOf(context).enabled) {
      clock.repeat();
    } else {
      clock.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduce = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(covariant PetCharacter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.motion != widget.motion) {
      clock.reset();
      _sync();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Alice，${widget.motion.label}',
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: clock,
        builder: (context, _) {
          final image = sheets[widget.motion.sheet];
          if (image == null) {
            return Image.asset(
              'assets/character.png',
              fit: BoxFit.contain,
              errorBuilder: (_, error, stack) =>
                  const Center(child: Icon(Icons.favorite_rounded, size: 96)),
            );
          }
          final ms = reduce ? 0 : (clock.value * 60000).round();
          return CustomPaint(painter: _SpritePainter(image, widget.motion, ms));
        },
      ),
    ),
  );
}

class _SpritePainter extends CustomPainter {
  final ui.Image image;
  final PetMotion motion;
  final int elapsed;
  _SpritePainter(this.image, this.motion, this.elapsed);
  @override
  void paint(Canvas canvas, Size size) {
    final rows = motion.sheet == 'activities' ? 3 : 2;
    final cellW = image.width / 4, cellH = image.height / rows;
    final frame = motion.frameAt(elapsed);
    final src = Rect.fromLTWH(frame * cellW, motion.row * cellH, cellW, cellH);
    final side =
        math.min(size.width * 1.25, size.height) *
        (motion == PetMotion.sleeping ? .78 : 1.0);
    final lift = motion == PetMotion.happy
        ? math.sin(elapsed / 145).abs() * 5
        : 0.0;
    final dst = Rect.fromLTWH(
      (size.width - side) / 2,
      size.height - side - lift,
      side,
      side,
    );
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_SpritePainter old) =>
      old.image != image ||
      old.motion != motion ||
      old.motion.frameAt(old.elapsed) != motion.frameAt(elapsed) ||
      motion == PetMotion.happy;
}
