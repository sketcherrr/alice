import 'dart:math' as math;

typedef BlockCell = (int, int);

/// Deterministic offline rules, separate from rendering and frame rate.
class FallingBlocks {
  static const width = 10, height = 20;
  static const shapes = <List<BlockCell>>[
    [(0, 1), (1, 1), (2, 1), (3, 1)],
    [(1, 0), (2, 0), (1, 1), (2, 1)],
    [(1, 0), (0, 1), (1, 1), (2, 1)],
    [(1, 0), (2, 0), (0, 1), (1, 1)],
    [(0, 0), (1, 0), (1, 1), (2, 1)],
    [(0, 0), (0, 1), (1, 1), (2, 1)],
    [(2, 0), (0, 1), (1, 1), (2, 1)],
  ];
  final math.Random random;
  final List<int> board = List.filled(width * height, 0);
  final List<int> queue = [];
  int piece = 0, rotation = 0, x = 3, y = -1, score = 0, lines = 0;
  int? held;
  bool usedHold = false, over = false, paused = true;
  double elapsed = 0;
  FallingBlocks({math.Random? random}) : random = random ?? math.Random() {
    reset();
  }
  int get level => lines ~/ 10;
  void _refill() {
    if (queue.length < 7)
      queue.addAll(List.generate(7, (i) => i)..shuffle(random));
  }

  void reset() {
    board.fillRange(0, board.length, 0);
    queue.clear();
    held = null;
    score = 0;
    lines = 0;
    over = false;
    paused = true;
    usedHold = false;
    _spawn();
  }

  List<BlockCell> cells({int? turn, int? kind}) {
    final id = kind ?? piece;
    var result = List<BlockCell>.from(shapes[id]);
    if (id == 1) return result;
    final size = id == 0 ? 4 : 3;
    for (var i = 0; i < (turn ?? rotation) % 4; i++) {
      result = result.map((c) => (size - 1 - c.$2, c.$1)).toList();
    }
    return result;
  }

  bool fits(int px, int py, int turn) => cells(turn: turn).every((c) {
    final cx = px + c.$1, cy = py + c.$2;
    return cx >= 0 &&
        cx < width &&
        cy < height &&
        cy >= -4 &&
        (cy < 0 || board[cy * width + cx] == 0);
  });
  void _spawn() {
    _refill();
    piece = queue.removeAt(0);
    rotation = 0;
    x = 3;
    y = -1;
    elapsed = 0;
    if (!fits(x, y, rotation)) over = true;
  }

  bool move(int dx, [int dy = 0]) {
    if (paused || over || !fits(x + dx, y + dy, rotation)) return false;
    x += dx;
    y += dy;
    return true;
  }

  void rotate() {
    if (paused || over) return;
    final next = (rotation + 1) % 4;
    for (final kick in const <BlockCell>[
      (0, 0),
      (-1, 0),
      (1, 0),
      (-2, 0),
      (2, 0),
      (0, -1),
      (0, -2),
    ]) {
      if (fits(x + kick.$1, y + kick.$2, next)) {
        x += kick.$1;
        y += kick.$2;
        rotation = next;
        return;
      }
    }
  }

  int get ghostY {
    var row = y;
    while (fits(x, row + 1, rotation)) {
      row++;
    }
    return row;
  }

  void hardDrop() {
    if (paused || over) return;
    final end = ghostY;
    score += (end - y) * 2;
    y = end;
    _lock();
  }

  void softDrop() {
    if (paused || over) return;
    if (move(0, 1)) {
      score++;
    } else {
      _lock();
    }
    elapsed = 0;
  }

  void hold() {
    if (paused || over || usedHold) return;
    final old = held;
    held = piece;
    if (old == null) {
      _spawn();
    } else {
      piece = old;
      rotation = 0;
      x = 3;
      y = -1;
      elapsed = 0;
      if (!fits(x, y, rotation)) over = true;
    }
    usedHold = true;
  }

  void _lock() {
    final occupied = cells().map((c) => (x + c.$1, y + c.$2)).toList();
    if (occupied.any((c) => c.$2 < 0)) {
      over = true;
      return;
    }
    for (final c in occupied) {
      board[c.$2 * width + c.$1] = piece + 1;
    }
    final remaining = <List<int>>[];
    for (var row = 0; row < height; row++) {
      final values = board.sublist(row * width, (row + 1) * width);
      if (values.any((v) => v == 0)) remaining.add(values);
    }
    final cleared = height - remaining.length;
    score += const [0, 100, 300, 500, 800][cleared] * (level + 1);
    lines += cleared;
    final next = <int>[
      for (var i = 0; i < cleared * width; i++) 0,
      ...remaining.expand((row) => row),
    ];
    board.setAll(0, next);
    usedHold = false;
    _spawn();
  }

  void tick(double dt) {
    if (paused || over) return;
    elapsed += dt.clamp(0.0, .1);
    final interval = math.max(.12, .75 - level * .055);
    if (elapsed >= interval) {
      elapsed -= interval;
      if (!move(0, 1)) _lock();
    }
  }
}

class Brick {
  final double x, y, width, height;
  final int row;
  int hits;
  Brick(this.x, this.y, this.width, this.height, this.row, this.hits);
}

class BrickBreaker {
  static const width = 300.0, height = 420.0, radius = 6.0;
  static const paddleWidth = 68.0, paddleY = 389.0, paddleHeight = 10.0;
  final bricks = <Brick>[];
  double paddle = width / 2,
      bx = width / 2,
      by = paddleY - radius - 1,
      vx = 90,
      vy = -180;
  int score = 0, lives = 3, level = 1;
  bool paused = true, attached = true, over = false, won = false;
  BrickBreaker() {
    reset();
  }
  void reset() {
    score = 0;
    lives = 3;
    level = 1;
    paused = true;
    over = false;
    won = false;
    paddle = width / 2;
    _wall();
    _attach();
  }

  void _wall() {
    bricks.clear();
    for (var row = 0; row < 4 + level; row++) {
      for (var col = 0; col < 6; col++) {
        bricks.add(
          Brick(
            15 + col * 45.0,
            40 + row * 22.0,
            40,
            16,
            row,
            level >= 2 && row == 0 ? 2 : 1,
          ),
        );
      }
    }
  }

  void _attach() {
    attached = true;
    bx = paddle;
    by = paddleY - radius - 1;
    vx = 85;
    vy = -(185 + level * 15.0);
  }

  void setPaddle(double center) {
    paddle = center.clamp(paddleWidth / 2 + 2, width - paddleWidth / 2 - 2);
    if (attached) bx = paddle;
  }

  void launch() {
    if (over) return;
    paused = false;
    attached = false;
  }

  void tick(double dt) {
    if (paused || over || attached) return;
    final span = dt.clamp(0.0, .1);
    final steps = math.max(1, (span * 240).ceil());
    for (var i = 0; i < steps && !over && !attached; i++) {
      _step(span / steps);
    }
  }

  void _step(double dt) {
    final oldX = bx, oldY = by;
    bx += vx * dt;
    by += vy * dt;
    if (bx < radius) {
      bx = radius;
      vx = vx.abs();
    }
    if (bx > width - radius) {
      bx = width - radius;
      vx = -vx.abs();
    }
    if (by < radius) {
      by = radius;
      vy = vy.abs();
    }
    if (vy > 0 &&
        oldY + radius <= paddleY &&
        by + radius >= paddleY &&
        bx >= paddle - paddleWidth / 2 - radius &&
        bx <= paddle + paddleWidth / 2 + radius) {
      by = paddleY - radius;
      final speed = math.min(340.0, math.sqrt(vx * vx + vy * vy) + 3);
      final angle = ((bx - paddle) / (paddleWidth / 2)).clamp(-1.0, 1.0) * 1.02;
      vx = speed * math.sin(angle);
      vy = -speed * math.cos(angle);
      if (vx.abs() < 25) vx = vx < 0 ? -25 : 25;
    }
    for (final brick in bricks) {
      if (brick.hits == 0) continue;
      final closestX = bx.clamp(brick.x, brick.x + brick.width),
          closestY = by.clamp(brick.y, brick.y + brick.height);
      final dx = bx - closestX, dy = by - closestY;
      if (dx * dx + dy * dy > radius * radius) continue;
      brick.hits--;
      score += brick.hits == 0 ? 10 * level : 5;
      if (oldY + radius <= brick.y) {
        by = brick.y - radius;
        vy = -vy.abs();
      } else if (oldY - radius >= brick.y + brick.height) {
        by = brick.y + brick.height + radius;
        vy = vy.abs();
      } else if (oldX < brick.x) {
        bx = brick.x - radius;
        vx = -vx.abs();
      } else {
        bx = brick.x + brick.width + radius;
        vx = vx.abs();
      }
      break;
    }
    if (bricks.every((b) => b.hits == 0)) {
      if (level == 3) {
        over = true;
        won = true;
        score += lives * 100;
      } else {
        level++;
        _wall();
        _attach();
      }
    } else if (by - radius > height) {
      lives--;
      if (lives == 0) {
        over = true;
      } else {
        _attach();
      }
    }
  }
}
