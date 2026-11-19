import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum PetMotion {
  idle,
  greeting,
  listening,
  thinking,
  happy,
  tea,
  sleeping,
  stretching,
}

extension MotionSpec on PetMotion {
  String get label => switch (this) {
    PetMotion.idle => '陪在你身边',
    PetMotion.greeting => '见到你很开心',
    PetMotion.listening => '我在听',
    PetMotion.thinking => '让我想一想',
    PetMotion.happy => '蹭蹭你的手',
    PetMotion.tea => '一起喝杯茶',
    PetMotion.sleeping => '小憩一会儿',
    PetMotion.stretching => '伸个懒腰，慢慢来',
  };
  String get sheet => switch (this) {
    PetMotion.idle || PetMotion.greeting => 'idle-v2',
    PetMotion.happy || PetMotion.stretching => 'social-v2',
    PetMotion.tea || PetMotion.sleeping => 'rest-v2',
    PetMotion.listening => 'calm',
    PetMotion.thinking => 'activities',
  };
  int get rows => sheet.endsWith('-v2')
      ? 4
      : sheet == 'activities'
      ? 3
      : 2;
  int get firstFrame => switch (this) {
    PetMotion.greeting || PetMotion.stretching || PetMotion.sleeping => 8,
    PetMotion.listening => 4,
    _ => 0,
  };
  List<int> get timing => switch (this) {
    PetMotion.idle => [2300, 240, 180, 100, 110, 130, 240, 1100],
    PetMotion.listening => [1300, 650, 140, 700],
    PetMotion.thinking => [900, 650, 140, 800],
    PetMotion.greeting => [260, 200, 200, 200, 200, 200, 230, 300],
    PetMotion.happy => [260, 220, 260, 300, 260, 240, 260, 400],
    PetMotion.tea => [700, 400, 450, 600, 900, 550, 450, 700],
    PetMotion.sleeping => [900, 900, 900, 900, 900, 900, 900, 900],
    PetMotion.stretching => [500, 550, 600, 900, 850, 700, 500, 500],
  };
  int frameAt(int elapsedMs) {
    final durations = timing;
    var t = elapsedMs % durations.reduce((a, b) => a + b);
    for (var i = 0; i < durations.length; i++) {
      if (t < durations[i]) return firstFrame + i;
      t -= durations[i];
    }
    return firstFrame;
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

/// Shared decoded sheets. No image decoding in the animation loop.
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
    for (final name in [
      'idle-v2',
      'social-v2',
      'rest-v2',
      'calm',
      'activities',
    ]) {
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
    active =
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached;
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
          return AnimatedSwitcher(
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 180),
            layoutBuilder: (current, previous) => Stack(
              fit: StackFit.expand,
              children: [...previous, if (current != null) current],
            ),
            child: CustomPaint(
              key: ValueKey(widget.motion),
              painter: _SpritePainter(image, widget.motion, ms, reduce),
            ),
          );
        },
      ),
    ),
  );
}

class _SpritePainter extends CustomPainter {
  final ui.Image image;
  final PetMotion motion;
  final int elapsed;
  final bool reduced;
  _SpritePainter(this.image, this.motion, this.elapsed, this.reduced);
  @override
  void paint(Canvas canvas, Size size) {
    final cellW = image.width / 4, cellH = image.height / motion.rows;
    final frame = motion.frameAt(elapsed);
    final src = Rect.fromLTWH(
      (frame % 4) * cellW,
      (frame ~/ 4) * cellH,
      cellW,
      cellH,
    );
    final side =
        math.min(size.width * 1.25, size.height - 10) *
        (motion == PetMotion.sleeping ? .78 : 1.0);
    final seconds = elapsed / 1000.0;
    final breath = reduced
        ? 0.0
        : math.sin(seconds * (motion == PetMotion.sleeping ? 1.35 : 1.8));
    final lean = reduced
        ? 0.0
        : math.sin(seconds * 1.1) *
              (motion == PetMotion.listening ? .018 : .006);
    final bounce = reduced || motion != PetMotion.happy
        ? 0.0
        : math.pow(math.sin(seconds * 4), 2).toDouble() * 5;
    canvas.save();
    canvas.translate(size.width / 2, size.height - 5 - bounce);
    canvas.rotate(lean);
    canvas.scale(1 - breath * .003, 1 + breath * .006);
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(-side / 2, -side, side, side),
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
    if (!reduced &&
        (motion == PetMotion.happy || motion == PetMotion.stretching)) {
      for (var i = 0; i < 3; i++) {
        final t = (seconds * .55 + i / 3) % 1;
        final x =
            size.width * (i.isEven ? .22 : .78) + math.sin(t * 6 + i) * 10;
        final y = size.height - side * (.42 + t * .37);
        final paint = Paint()
          ..color =
              (motion == PetMotion.happy
                      ? const Color(0xFFE8B2C3)
                      : const Color(0xFFB1C6E1))
                  .withValues(alpha: math.sin(t * math.pi) * .7);
        if (motion == PetMotion.happy) {
          final heart = Path()
            ..moveTo(x, y + 5)
            ..cubicTo(x - 13, y - 2, x - 5, y - 10, x, y - 4)
            ..cubicTo(x + 5, y - 10, x + 13, y - 2, x, y + 5);
          canvas.drawPath(heart, paint);
        } else {
          canvas.drawPath(
            Path()
              ..moveTo(x, y - 6)
              ..lineTo(x + 2, y - 2)
              ..lineTo(x + 6, y)
              ..lineTo(x + 2, y + 2)
              ..lineTo(x, y + 6)
              ..lineTo(x - 2, y + 2)
              ..lineTo(x - 6, y)
              ..lineTo(x - 2, y - 2)
              ..close(),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_SpritePainter old) =>
      old.image != image ||
      old.motion != motion ||
      old.elapsed != elapsed ||
      old.reduced != reduced;
}
