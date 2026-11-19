import 'dart:math';
import '../apps/companion/lib/arcade_engine.dart';

void check(bool value, String description) {
  if (!value) throw StateError(description);
}

void runArcadeChecks() {
  final blocks = FallingBlocks(random: Random(42));
  check(
    {blocks.piece, ...blocks.queue.take(6)}.length == 7,
    'Seven-bag must include every piece once',
  );
  final start = blocks.y;
  blocks.tick(.1);
  blocks.hardDrop();
  check(blocks.y == start && blocks.score == 0, 'Paused board changed');
  blocks.paused = false;
  blocks.piece = 0;
  blocks.rotation = 0;
  blocks.x = 3;
  blocks.y = 0;
  for (var x = 0; x < 10; x++) {
    if (x < 3 || x > 6) blocks.board[19 * 10 + x] = 1;
  }
  check(blocks.ghostY == 18, 'Landing preview missed floor');
  blocks.hardDrop();
  check(
    blocks.lines == 1 &&
        blocks.score >= 100 &&
        blocks.board.every((v) => v == 0),
    'Line clear or scoring failed',
  );
  blocks.hold();
  final held = blocks.held;
  blocks.hold();
  check(blocks.held == held, 'Hold must be limited to once per piece');
  blocks.piece = 0;
  blocks.rotation = 1;
  blocks.x = -2;
  blocks.y = 5;
  check(
    blocks.fits(blocks.x, blocks.y, blocks.rotation),
    'Invalid wall-kick fixture',
  );
  blocks.rotate();
  check(
    blocks.fits(blocks.x, blocks.y, blocks.rotation),
    'Wall rotation left board bounds',
  );
  blocks.reset();
  blocks.paused = false;
  blocks.piece = 2;
  blocks.y = -1;
  blocks.board.fillRange(0, 10, 1);
  blocks.softDrop();
  check(blocks.over, 'Top-out must end game without negative indexing');
  blocks.reset();
  check(
    !blocks.over && blocks.paused && blocks.lines == 0 && blocks.held == null,
    'Restart retained previous state',
  );

  final breaker = BrickBreaker();
  breaker.launch();
  breaker.bx = 7;
  breaker.by = 300;
  breaker.vx = -200;
  breaker.vy = -30;
  breaker.tick(.03);
  check(
    breaker.vx > 0 && breaker.bx >= BrickBreaker.radius,
    'Side wall reflection failed',
  );
  breaker.bx = breaker.paddle;
  breaker.by = BrickBreaker.paddleY - 7;
  breaker.vy = 200;
  breaker.vx = 0;
  breaker.tick(.04);
  check(
    breaker.vy < 0 && breaker.by < BrickBreaker.paddleY,
    'Ball tunneled through paddle',
  );
  final first = breaker.bricks.first;
  breaker.bx = first.x + first.width / 2;
  breaker.by = first.y - 8;
  breaker.vx = 0;
  breaker.vy = 200;
  breaker.tick(.025);
  check(
    first.hits == 0 && breaker.score == 10 && breaker.vy < 0,
    'Brick collision/scoring failed',
  );
  breaker.by = BrickBreaker.height + 7;
  breaker.vy = 200;
  breaker.tick(.01);
  check(
    breaker.lives == 2 && breaker.attached,
    'Lost ball should wait for a new serve',
  );
  breaker.setPaddle(-100);
  check(breaker.paddle >= BrickBreaker.paddleWidth / 2, 'Paddle escaped board');
  breaker.launch();
  breaker.paused = true;
  final position = (breaker.bx, breaker.by);
  breaker.tick(.1);
  check(position == (breaker.bx, breaker.by), 'Paused ball moved');
  breaker.paused = false;
  for (final brick in breaker.bricks) {
    brick.hits = 0;
  }
  breaker.tick(.01);
  check(
    breaker.level == 2 && breaker.attached,
    'Next level did not wait for serve',
  );
  breaker.level = 3;
  breaker.launch();
  for (final brick in breaker.bricks) {
    brick.hits = 0;
  }
  breaker.tick(.01);
  check(breaker.over && breaker.won, 'Third wall should complete game');
  breaker.reset();
  check(
    !breaker.over && breaker.lives == 3 && breaker.score == 0 && breaker.paused,
    'Breakout restart failed',
  );
  final a = BrickBreaker()..launch(), b = BrickBreaker()..launch();
  for (var i = 0; i < 120; i++) {
    a.tick(1 / 120);
  }
  for (var i = 0; i < 60; i++) {
    b.tick(1 / 60);
  }
  check(
    (a.bx - b.bx).abs() < .01 &&
        (a.by - b.by).abs() < .01 &&
        a.score == b.score,
    'Ball physics depends on display frame rate',
  );
  print(
    'PASS: seven-bag, pause, line clear, scoring, hold, wall kicks, top-out and restart.',
  );
  print(
    'PASS: wall/paddle/brick collisions, lives, serve, levels, win, restart and frame-rate independence.',
  );
}

void main() => runArcadeChecks();
