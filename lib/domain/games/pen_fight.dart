import 'dart:math';

import 'package:equatable/equatable.dart';

/// Rules and physics of Pen Fight: pure Dart, so both phones can run exactly the same
/// simulation from the same flick.
///
/// The desk is [deskWidth] x [deskHeight] units. A world is always seen from one player's side:
/// that player's pen ([PenWorld.own]) is at the bottom, the partner's at the top. A message
/// from the partner is turned around ([PenBody.mirrored]) before it is used.
class PenFight {
  const PenFight._();

  static const deskWidth  = 1.0;
  static const deskHeight = 1.4;
  static const penRadius  = 0.07;
  /// One simulation step, in seconds. Fixed, so every phone takes the same steps.
  static const stepSeconds = 1 / 60;
  /// A pen that is already off the desk slows down faster.
  static const fallFriction = 0.9;
  /// How much speed a hit keeps (1 would be a perfect bounce).
  static const restitution = 0.9;
  /// Below this a pen counts as stopped.
  static const stopSpeed   = 0.02;
}

/// A fixed obstacle (a rubber) on the desk: pens bounce off it.
class PenObstacle extends Equatable {
  const PenObstacle(this.x, this.y, this.radius);
  final double x, y, radius;

  @override
  List<Object?> get props => [x, y, radius];
}

/// How hard the game is: how far a flick can send a pen, how slippery the desk is and what is in the way.
/// Both partners play the same level (it is stored in the game session).
///
/// Obstacle layouts are symmetric about the middle of the desk, so both players see the same desk.
enum PenDifficulty {
  easy('easy', 'Easy', 'One rubber in the middle. Long flicks.',
      maxSpeed: 1.5, friction: 0.972, obstacles: [PenObstacle(0.5, 0.7, 0.07)]),
  normal('normal', 'Normal', 'Two rubbers and shorter flicks.',
      maxSpeed: 1.2, friction: 0.965, obstacles: [PenObstacle(0.3, 0.7, 0.07), PenObstacle(0.7, 0.7, 0.07)]),
  hard('hard', 'Hard', 'Three rubbers, a slippery desk and short flicks.',
      maxSpeed: 1.0, friction: 0.96, obstacles: [PenObstacle(0.5, 0.7, 0.07), PenObstacle(0.25, 0.5, 0.06), PenObstacle(0.75, 0.9, 0.06)]);

  const PenDifficulty(this.key, this.label, this.description,
      {required this.maxSpeed, required this.friction, required this.obstacles});

  final String key, label, description;
  /// Speed of the hardest flick, in desk units per second.
  final double maxSpeed;
  /// Speed kept after each step (the desk's friction): lower is stickier.
  final double friction;
  final List<PenObstacle> obstacles;

  static PenDifficulty fromKey(Object? key) {
    for (final d in values) {
      if (d.key == key) return d;
    }
    return normal;
  }
}

/// One pen: where it is, how fast it moves, which way it points and whether it fell off the desk.
class PenBody extends Equatable {
  const PenBody({
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
    this.angle = 0,
    this.fell = false,
  });

  final double x, y, vx, vy;
  /// Direction the pen points, in radians (0 is right, pi/2 is down).
  final double angle;
  final bool   fell;

  double get speed => sqrt(vx * vx + vy * vy);
  bool   get moving => speed >= PenFight.stopSpeed;

  PenBody copyWith({double? x, double? y, double? vx, double? vy, double? angle, bool? fell}) => PenBody(
        x: x ?? this.x, y: y ?? this.y, vx: vx ?? this.vx, vy: vy ?? this.vy,
        angle: angle ?? this.angle, fell: fell ?? this.fell,
      );

  /// The same pen seen from the other side of the desk.
  PenBody mirrored() => PenBody(
        x: PenFight.deskWidth - x,
        y: PenFight.deskHeight - y,
        vx: -vx,
        vy: -vy,
        angle: angle + pi,
        fell: fell,
      );

  bool get isOnDesk => x >= 0 && x <= PenFight.deskWidth && y >= 0 && y <= PenFight.deskHeight;

  PenBody _advance(double deskFriction) {
    var nx = x + vx * PenFight.stepSeconds;
    var ny = y + vy * PenFight.stepSeconds;
    var f  = fell ? PenFight.fallFriction : deskFriction;
    var nvx = vx * f, nvy = vy * f;
    if (sqrt(nvx * nvx + nvy * nvy) < PenFight.stopSpeed) { nvx = 0; nvy = 0; }
    final moved = PenBody(x: nx, y: ny, vx: nvx, vy: nvy, angle: angle, fell: fell);
    final turned = moved.speed > 0.05 ? atan2(nvy, nvx) : angle;
    final off = !fell && !moved.isOnDesk;
    return moved.copyWith(angle: turned, fell: fell || off);
  }

  /// `[x, y, vx, vy, angle, fell]`, for the channel.
  List<Object> toJson() => [x, y, vx, vy, angle, fell ? 1 : 0];

  static PenBody? fromJson(Object? json) {
    if (json is! List || json.length < 6) return null;
    final n = json.sublist(0, 5);
    if (n.any((v) => v is! num)) return null;
    return PenBody(
      x: (n[0] as num).toDouble(), y: (n[1] as num).toDouble(),
      vx: (n[2] as num).toDouble(), vy: (n[3] as num).toDouble(),
      angle: (n[4] as num).toDouble(),
      fell: json[5] == 1,
    );
  }

  @override
  List<Object?> get props => [x, y, vx, vy, angle, fell];
}

/// Who came out on top of a round (from the point of view of the phone looking at it).
enum PenOutcome { none, ownWon, otherWon, draw }

/// Both pens on the desk.
class PenWorld extends Equatable {
  const PenWorld({required this.own, required this.other, this.bumps = 0, this.difficulty = PenDifficulty.normal});

  /// The pens at the start of a round: yours at the bottom, your partner's at the top, facing each other.
  factory PenWorld.start([PenDifficulty difficulty = PenDifficulty.normal]) => PenWorld(
        own:   const PenBody(x: 0.5, y: 1.05, angle: -pi / 2),
        other: const PenBody(x: 0.5, y: 0.35, angle: pi / 2),
        difficulty: difficulty,
      );

  final PenBody own, other;
  /// Sets the flick power, friction and obstacles. Not sent over the channel: both phones know it from the session.
  final PenDifficulty difficulty;
  /// How many times the pens have hit each other since this world was created (for the sound).
  final int bumps;

  PenWorld copyWith({PenBody? own, PenBody? other, int? bumps, PenDifficulty? difficulty}) => PenWorld(
      own: own ?? this.own, other: other ?? this.other, bumps: bumps ?? this.bumps, difficulty: difficulty ?? this.difficulty);

  /// Nothing moves any more.
  bool get settled => !own.moving && !other.moving;

  PenOutcome get outcome {
    if (own.fell && other.fell) return PenOutcome.draw;
    if (other.fell) return PenOutcome.ownWon;
    if (own.fell)   return PenOutcome.otherWon;
    return PenOutcome.none;
  }

  /// Gives your pen a flick. [dx], [dy] is the direction (any length), [power] 0..1.
  PenWorld flicked(double dx, double dy, double power) {
    final len = sqrt(dx * dx + dy * dy);
    if (len == 0) return this;
    final p = power.clamp(0.0, 1.0) * difficulty.maxSpeed;
    final vx = dx / len * p, vy = dy / len * p;
    return copyWith(own: own.copyWith(vx: vx, vy: vy, angle: atan2(vy, vx)));
  }

  /// The world as the partner sees it.
  PenWorld mirrored() => PenWorld(own: other.mirrored(), other: own.mirrored(), bumps: bumps, difficulty: difficulty);

  /// One fixed step of the simulation.
  PenWorld step() {
    var a = own._advance(difficulty.friction);
    var b = other._advance(difficulty.friction);
    var hits = bumps;

    if (!a.fell && !b.fell) {
      final dx = b.x - a.x, dy = b.y - a.y;
      final dist = sqrt(dx * dx + dy * dy);
      const minDist = PenFight.penRadius * 2;
      if (dist < minDist && dist > 0) {
        final nx = dx / dist, ny = dy / dist;
        final approach = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
        var avx = a.vx, avy = a.vy, bvx = b.vx, bvy = b.vy;
        if (approach < 0) {
          // Two equal pens: they swap the speed along the line between them (a bit is lost).
          final j = -(1 + PenFight.restitution) * approach / 2;
          avx -= j * nx; avy -= j * ny;
          bvx += j * nx; bvy += j * ny;
          hits++;
        }
        final push = (minDist - dist) / 2;
        a = a.copyWith(x: a.x - nx * push, y: a.y - ny * push, vx: avx, vy: avy,
            angle: sqrt(avx * avx + avy * avy) > 0.05 ? atan2(avy, avx) : a.angle);
        b = b.copyWith(x: b.x + nx * push, y: b.y + ny * push, vx: bvx, vy: bvy,
            angle: sqrt(bvx * bvx + bvy * bvy) > 0.05 ? atan2(bvy, bvx) : b.angle);
      }
    }
    // The rubbers: a pen bounces off them (a pen that already fell is past caring).
    for (final o in difficulty.obstacles) {
      a = _bounce(a, o);
      b = _bounce(b, o);
    }
    return PenWorld(own: a, other: b, bumps: hits, difficulty: difficulty);
  }

  static PenBody _bounce(PenBody pen, PenObstacle o) {
    if (pen.fell) return pen;
    final dx = pen.x - o.x, dy = pen.y - o.y;
    final dist = sqrt(dx * dx + dy * dy);
    final minDist = PenFight.penRadius + o.radius;
    if (dist >= minDist || dist == 0) return pen;
    final nx = dx / dist, ny = dy / dist;
    var vx = pen.vx, vy = pen.vy;
    final into = vx * nx + vy * ny;
    if (into < 0) {
      vx -= (1 + PenFight.restitution) * into * nx;
      vy -= (1 + PenFight.restitution) * into * ny;
    }
    return pen.copyWith(
      x: o.x + nx * minDist, y: o.y + ny * minDist, vx: vx, vy: vy,
      angle: sqrt(vx * vx + vy * vy) > 0.05 ? atan2(vy, vx) : pen.angle,
    );
  }

  @override
  List<Object?> get props => [own, other, bumps, difficulty];
}

/// What the two phones send each other.
enum PenMessageType { hello, here, bye, flick, settled, next }

class PenMessage extends Equatable {
  const PenMessage({required this.type, required this.from, this.seq = 0, this.world, this.round = 0});

  final PenMessageType type;
  final String         from;
  /// Counts the flicks of a game, so a message that arrives twice is used once.
  final int            seq;
  /// The pens as the SENDER sees them (the receiver turns them around with [worldForReceiver]).
  final PenWorld?      world;
  /// For [PenMessageType.next]: the number of the round that starts.
  final int            round;

  PenWorld? get worldForReceiver => world?.mirrored();

  Map<String, dynamic> toJson() => {
        // Not 'type' or 'event': the channel adds those to what it delivers and would overwrite them.
        'kind': type.name,
        'from': from,
        'seq': seq,
        'round': round,
        if (world != null) 'own': world!.own.toJson(),
        if (world != null) 'other': world!.other.toJson(),
      };

  static PenMessage? fromJson(Map<String, dynamic> json) {
    final type = PenMessageType.values.where((t) => t.name == json['kind']).firstOrNull;
    final from = json['from'];
    if (type == null || from is! String) return null;
    final own = PenBody.fromJson(json['own']);
    final other = PenBody.fromJson(json['other']);
    if ((type == PenMessageType.flick || type == PenMessageType.settled) && (own == null || other == null)) return null;
    return PenMessage(
      type: type,
      from: from,
      seq: json['seq'] is int ? json['seq'] as int : 0,
      round: json['round'] is int ? json['round'] as int : 0,
      world: own != null && other != null ? PenWorld(own: own, other: other) : null,
    );
  }

  @override
  List<Object?> get props => [type, from, seq, world, round];
}
