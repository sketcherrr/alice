import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'arcade_engine.dart';

enum ArcadeKind { tetris, breakout }

class ArcadeRoom extends StatefulWidget {
  final ArcadeKind kind;
  final int best;
  final Future<void> Function(String runId, int score) onResult;
  const ArcadeRoom({
    super.key,
    required this.kind,
    this.best = 0,
    required this.onResult,
  });
  @override
  State<ArcadeRoom> createState() => _ArcadeRoomState();
}

class _ArcadeRoomState extends State<ArcadeRoom>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final blocks = FallingBlocks(), breaker = BrickBreaker();
  final focus = FocusNode();
  final heldKeys = <LogicalKeyboardKey>{};
  late final Ticker ticker;
  Duration? previous;
  String runId = '';
  bool started = false, submitted = false;
  int best = 0;
  String? saveStatus;
  bool get isBlocks => widget.kind == ArcadeKind.tetris;
  bool get paused => isBlocks ? blocks.paused : breaker.paused;
  bool get over => isBlocks ? blocks.over : breaker.over;
  int get score => isBlocks ? blocks.score : breaker.score;
  @override
  void initState() {
    super.initState();
    best = widget.best;
    _newRun();
    WidgetsBinding.instance.addObserver(this);
    ticker = createTicker((elapsed) {
      final dt = previous == null
          ? 0.0
          : (elapsed - previous!).inMicroseconds / 1000000;
      previous = elapsed;
      if (!started || paused || over) return;
      if (!isBlocks) {
        final direction =
            (heldKeys.contains(LogicalKeyboardKey.arrowRight) ? 1 : 0) -
            (heldKeys.contains(LogicalKeyboardKey.arrowLeft) ? 1 : 0);
        breaker.setPaddle(
          breaker.paddle + direction * 310 * dt.clamp(0.0, .05),
        );
      }
      setState(() {
        if (isBlocks) {
          blocks.tick(dt);
        } else {
          breaker.tick(dt);
        }
      });
      _saveResult();
    })..start();
  }

  void _newRun() {
    runId =
        '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 30)}';
    submitted = false;
    saveStatus = null;
  }

  void _pause() {
    heldKeys.clear();
    if (!mounted || over || !started) return;
    setState(() {
      blocks.paused = true;
      breaker.paused = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker.dispose();
    focus.dispose();
    super.dispose();
  }

  void _saveResult() {
    if (!over || submitted) return;
    submitted = true;
    final id = runId, finalScore = score;
    best = math.max(best, finalScore);
    widget
        .onResult(id, finalScore)
        .then((_) {
          if (mounted && runId == id) setState(() => saveStatus = '成绩已记在本机');
        })
        .catchError((Object _) {
          if (mounted && runId == id) setState(() => saveStatus = '这次成绩没能保存');
        });
  }

  void _resume() {
    setState(() {
      started = true;
      blocks.paused = false;
      breaker.paused = false;
      previous = null;
    });
    focus.requestFocus();
  }

  void _restart() {
    setState(() {
      blocks.reset();
      breaker.reset();
      _newRun();
      started = false;
    });
    _resume();
  }

  void _command(String action) {
    if (action == 'pause') {
      if (over) return;
      if (paused) {
        _resume();
      } else {
        _pause();
      }
      return;
    }
    if (!started || paused || over) return;
    setState(() {
      if (isBlocks) {
        switch (action) {
          case 'left':
            blocks.move(-1);
          case 'right':
            blocks.move(1);
          case 'rotate':
            blocks.rotate();
          case 'down':
            blocks.softDrop();
          case 'drop':
            blocks.hardDrop();
          case 'hold':
            blocks.hold();
        }
      } else {
        switch (action) {
          case 'left':
            breaker.setPaddle(breaker.paddle - 22);
          case 'right':
            breaker.setPaddle(breaker.paddle + 22);
          case 'drop':
            breaker.launch();
        }
      }
    });
    focus.requestFocus();
    _saveResult();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyUpEvent) {
      heldKeys.remove(key);
      return KeyEventResult.ignored;
    }
    final action = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.arrowLeft: 'left',
      LogicalKeyboardKey.arrowRight: 'right',
      LogicalKeyboardKey.arrowUp: 'rotate',
      LogicalKeyboardKey.arrowDown: 'down',
      LogicalKeyboardKey.space: 'drop',
      LogicalKeyboardKey.keyC: 'hold',
      LogicalKeyboardKey.keyP: 'pause',
    }[key];
    if (action == null) return KeyEventResult.ignored;
    if (event is KeyRepeatEvent && ['drop', 'pause', 'hold'].contains(action))
      return KeyEventResult.handled;
    if (!isBlocks && (action == 'left' || action == 'right')) {
      heldKeys.add(key);
    } else {
      _command(action);
    }
    return KeyEventResult.handled;
  }

  Widget _control(String action, IconData icon, String title) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: title,
        child: FilledButton.tonal(
          key: ValueKey('arcade-$action'),
          onPressed: !started || paused || over ? null : () => _command(action),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
            minimumSize: const Size(40, 44),
          ),
          child: Icon(icon, size: 21),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    autofocus: true,
    onKeyEvent: _key,
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isBlocks ? '俄罗斯方块' : '打砖块',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('arcade-pause'),
              tooltip: paused ? '继续游戏' : '暂停游戏',
              onPressed: over ? null : () => _command('pause'),
              icon: Icon(
                paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              ),
            ),
            IconButton(
              key: const ValueKey('close-arcade'),
              tooltip: '离开游戏',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 18,
          children: [
            Text('得分 $score', key: const ValueKey('arcade-score')),
            Text('最佳 $best'),
            Text(
              isBlocks
                  ? '消行 ${blocks.lines}'
                  : '爱心 ${breaker.lives} · 第 ${breaker.level} 关',
            ),
          ],
        ),
        if (isBlocks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('下一个 ', style: TextStyle(fontSize: 11)),
                CustomPaint(
                  size: const Size(45, 25),
                  painter: _PiecePreview(blocks.queue.first),
                ),
                const SizedBox(width: 20),
                const Text('暂存 ', style: TextStyle(fontSize: 11)),
                CustomPaint(
                  size: const Size(45, 25),
                  painter: _PiecePreview(blocks.held),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: isBlocks ? .5 : 300 / 420,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  void paddle(double x) {
                    if (!isBlocks && started && !paused && !over)
                      setState(
                        () => breaker.setPaddle(
                          x / constraints.maxWidth * BrickBreaker.width,
                        ),
                      );
                  }

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Semantics(
                          label: isBlocks
                              ? '俄罗斯方块棋盘，方向键移动和旋转，空格落下'
                              : '打砖块，左右键或拖动挡板，空格发球',
                          child: MouseRegion(
                            onHover: (e) => paddle(e.localPosition.dx),
                            child: GestureDetector(
                              onPanStart: (d) => paddle(d.localPosition.dx),
                              onPanUpdate: (d) => paddle(d.localPosition.dx),
                              onTapUp: (d) {
                                paddle(d.localPosition.dx);
                                if (!isBlocks) _command('drop');
                              },
                              child: CustomPaint(
                                key: const ValueKey('arcade-board'),
                                painter: isBlocks
                                    ? _BlocksPainter(blocks)
                                    : _BreakerPainter(breaker),
                              ),
                            ),
                          ),
                        ),
                        if (!started || paused || over)
                          ColoredBox(
                            color: const Color(0xDEEFF0F8),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.sports_esports_outlined,
                                      size: 35,
                                      color: Color(0xFF7B83B6),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      over
                                          ? (!isBlocks && breaker.won
                                                ? '三关通关，漂亮！'
                                                : '这局玩得不错')
                                          : started
                                          ? '暂停一下'
                                          : 'Alice 陪你玩',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      over
                                          ? '本局 $score 分'
                                          : isBlocks
                                          ? '凑满一行，就会消除'
                                          : '接住小球，击碎所有砖块',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 14),
                                    FilledButton(
                                      key: const ValueKey('arcade-start'),
                                      onPressed: over ? _restart : _resume,
                                      child: Text(
                                        over
                                            ? '再来一局'
                                            : started
                                            ? '继续'
                                            : '开始',
                                      ),
                                    ),
                                    if (saveStatus != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          saveStatus!,
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (!isBlocks && breaker.attached && started && !paused && !over)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('点棋盘或按空格发球', style: TextStyle(fontSize: 12)),
          ),
        Row(
          children: [
            _control('left', Icons.arrow_back_rounded, '向左'),
            if (isBlocks) _control('rotate', Icons.rotate_right_rounded, '旋转'),
            _control(
              'drop',
              Icons.vertical_align_bottom_rounded,
              isBlocks ? '直接落下' : '发球',
            ),
            if (isBlocks) _control('down', Icons.arrow_downward_rounded, '下降'),
            _control('right', Icons.arrow_forward_rounded, '向右'),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isBlocks)
              TextButton(
                onPressed: started && !paused && !over
                    ? () => _command('hold')
                    : null,
                child: const Text('暂存 C'),
              ),
            TextButton(
              onPressed: started ? _restart : null,
              child: const Text('重新开始'),
            ),
          ],
        ),
        Text(
          isBlocks
              ? '← → 移动 · ↑ 旋转 · ↓ 下降 · 空格落下 · P 暂停'
              : '鼠标 / 拖动 / ← → 移动 · 空格发球 · P 暂停',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, color: Color(0xFF74768D)),
        ),
      ],
    ),
  );
}

const _colors = [
  Color(0xFF9CCDD8),
  Color(0xFFE8C784),
  Color(0xFFB3A1D4),
  Color(0xFF9DC7A9),
  Color(0xFFE4AAA9),
  Color(0xFF8DAAD4),
  Color(0xFFE0B487),
];
void _block(Canvas canvas, Rect rect, Color color) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect.deflate(.8), const Radius.circular(3)),
    Paint()..color = color,
  );
  canvas.drawLine(
    rect.topLeft + const Offset(3, 3),
    rect.topRight + const Offset(-3, 3),
    Paint()
      ..color = Colors.white.withValues(alpha: .5)
      ..strokeWidth = 2,
  );
}

class _PiecePreview extends CustomPainter {
  final int? piece;
  _PiecePreview(this.piece);
  @override
  void paint(Canvas canvas, Size size) {
    if (piece == null) return;
    for (final c in FallingBlocks.shapes[piece!]) {
      _block(
        canvas,
        Rect.fromLTWH(c.$1 * 10, c.$2 * 10, 10, 10),
        _colors[piece!],
      );
    }
  }

  @override
  bool shouldRepaint(_PiecePreview old) => old.piece != piece;
}

class _BlocksPainter extends CustomPainter {
  final FallingBlocks game;
  _BlocksPainter(this.game);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF222840),
    );
    final cell = size.width / 10;
    final grid = Paint()
      ..color = const Color(0xFF30374D)
      ..strokeWidth = .6;
    for (var x = 1; x < 10; x++)
      canvas.drawLine(Offset(x * cell, 0), Offset(x * cell, size.height), grid);
    for (var y = 1; y < 20; y++)
      canvas.drawLine(Offset(0, y * cell), Offset(size.width, y * cell), grid);
    for (var i = 0; i < game.board.length; i++) {
      if (game.board[i] > 0)
        _block(
          canvas,
          Rect.fromLTWH((i % 10) * cell, (i ~/ 10) * cell, cell, cell),
          _colors[game.board[i] - 1],
        );
    }
    if (game.over) return;
    for (final c in game.cells()) {
      final ghost = Rect.fromLTWH(
        (game.x + c.$1) * cell,
        (game.ghostY + c.$2) * cell,
        cell,
        cell,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(ghost.deflate(2), const Radius.circular(3)),
        Paint()
          ..color = _colors[game.piece].withValues(alpha: .4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      if (game.y + c.$2 >= 0)
        _block(
          canvas,
          Rect.fromLTWH(
            (game.x + c.$1) * cell,
            (game.y + c.$2) * cell,
            cell,
            cell,
          ),
          _colors[game.piece],
        );
    }
  }

  @override
  bool shouldRepaint(_BlocksPainter old) => true;
}

class _BreakerPainter extends CustomPainter {
  final BrickBreaker game;
  _BreakerPainter(this.game);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 300, size.height / 420);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 300, 420),
      Paint()..color = const Color(0xFF222840),
    );
    for (var i = 0; i < 24; i++)
      canvas.drawCircle(
        Offset((i * 73 % 290) + 5.0, (i * 137 % 410) + 5.0),
        1,
        Paint()..color = const Color(0xFF424D68),
      );
    for (final b in game.bricks) {
      if (b.hits > 0) {
        _block(
          canvas,
          Rect.fromLTWH(b.x, b.y, b.width, b.height),
          _colors[b.row % _colors.length],
        );
        if (b.hits > 1)
          canvas.drawCircle(
            Offset(b.x + b.width / 2, b.y + b.height / 2),
            2,
            Paint()..color = Colors.white,
          );
      }
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          game.paddle - BrickBreaker.paddleWidth / 2,
          BrickBreaker.paddleY,
          BrickBreaker.paddleWidth,
          BrickBreaker.paddleHeight,
        ),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFFBBC4F0),
    );
    canvas.drawCircle(
      Offset(game.bx, game.by),
      BrickBreaker.radius + 3,
      Paint()..color = const Color(0x33FDF4CF),
    );
    canvas.drawCircle(
      Offset(game.bx, game.by),
      BrickBreaker.radius,
      Paint()..color = const Color(0xFFFDF4CF),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BreakerPainter old) => true;
}
