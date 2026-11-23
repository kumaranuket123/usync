import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:usync/domain/games/pen_fight.dart';

PenWorld _run(PenWorld w, {int max = 2000}) {
  var i = 0;
  while (!w.settled && i++ < max) {
    w = w.step();
  }
  return w;
}

void main() {
  test('the same flick always ends the same way', () {
    final a = _run(PenWorld.start().flicked(0.1, -1, 0.9));
    final b = _run(PenWorld.start().flicked(0.1, -1, 0.9));
    expect(a, b);
  });

  test('friction stops a pen', () {
    final w = _run(PenWorld.start().flicked(0, -1, 0.3));
    expect(w.settled, isTrue);
    expect(w.own.fell, isFalse);
    expect(w.own.y, lessThan(1.05));
  });

  test('a flick of no length does nothing', () {
    expect(PenWorld.start().flicked(0, 0, 1), PenWorld.start());
  });

  test('a hit passes speed on to the other pen and counts as a bump', () {
    var w = PenWorld.start().flicked(0, -1, 1);
    var otherMoved = false;
    for (var i = 0; i < 300 && !otherMoved; i++) {
      w = w.step();
      otherMoved = w.other.moving;
    }
    expect(otherMoved, isTrue);
    expect(w.bumps, greaterThanOrEqualTo(1));
    expect(w.other.vy, lessThan(0), reason: 'pushed away from the flicker');
  });

  test('a hard flick off the side makes the pen fall and the other side win', () {
    final w = _run(PenWorld.start().flicked(1, 0, 1));
    expect(w.own.fell, isTrue);
    expect(w.outcome, PenOutcome.otherWon);
  });

  test('knocking the other pen off the desk is a win', () {
    // Put the partner's pen near the top edge and hit it straight on.
    var w = const PenWorld(
      own:   PenBody(x: 0.5, y: 0.6, angle: -pi / 2),
      other: PenBody(x: 0.5, y: 0.2, angle: pi / 2),
    ).flicked(0, -1, 1);
    w = _run(w);
    expect(w.other.fell, isTrue);
    expect(w.own.fell, isFalse);
    expect(w.outcome, PenOutcome.ownWon);
  });

  test('both pens falling is a draw', () {
    const w = PenWorld(own: PenBody(x: -1, y: 0, fell: true), other: PenBody(x: 3, y: 0, fell: true));
    expect(w.outcome, PenOutcome.draw);
  });

  test('turning the desk around twice gives the same world', () {
    final w = PenWorld.start().flicked(0.3, -1, 0.7).step();
    final back = w.mirrored().mirrored();
    expect(back.own.x, closeTo(w.own.x, 1e-9));
    expect(back.other.y, closeTo(w.other.y, 1e-9));
    expect(back.own.vx, closeTo(w.own.vx, 1e-9));
  });

  test('the partner sees my pen at the top, mirrored', () {
    final mine = PenWorld.start();
    final theirs = mine.mirrored();
    expect(theirs.other.x, closeTo(mine.own.x, 1e-9));
    expect(theirs.other.y, closeTo(PenFight.deskHeight - mine.own.y, 1e-9));
    expect(theirs.other.y, lessThan(theirs.own.y), reason: 'the partner\'s pen is at the top for me');
  });

  group('difficulty', () {
    test('a harder level sends a flick less far and has more rubbers', () {
      final easy = _run(PenWorld.start(PenDifficulty.easy).flicked(1, -0.3, 0.5));
      final hard = _run(PenWorld.start(PenDifficulty.hard).flicked(1, -0.3, 0.5));
      expect((hard.own.x - 0.5).abs(), lessThan((easy.own.x - 0.5).abs()));
      expect(PenDifficulty.hard.obstacles.length, greaterThan(PenDifficulty.easy.obstacles.length));
    });

    test('a full flick at the other pen at Hard cannot knock it off the desk in one go', () {
      // Aim round the middle rubber, straight up the side.
      final w = _run(PenWorld.start(PenDifficulty.hard).flicked(0.2, -1, 1));
      expect(w.outcome, PenOutcome.none);
    });

    test('a pen bounces off a rubber instead of passing through', () {
      var w = PenWorld.start(PenDifficulty.easy).flicked(0, -1, 1); // straight at the middle rubber
      var minY = 9.0;
      for (var i = 0; i < 600; i++) {
        w = w.step();
        if (w.own.y < minY) minY = w.own.y;
      }
      const o = PenObstacle(0.5, 0.7, 0.07);
      expect(minY, greaterThanOrEqualTo(o.y + o.radius + PenFight.penRadius - 1e-6));
    });

    test('every layout is the same seen from the other side', () {
      for (final d in PenDifficulty.values) {
        final spots = d.obstacles.map((o) => [o.x.toStringAsFixed(6), o.y.toStringAsFixed(6)]).toSet();
        final turned = d.obstacles.map((o) => [(PenFight.deskWidth - o.x).toStringAsFixed(6), (PenFight.deskHeight - o.y).toStringAsFixed(6)]).toSet();
        expect(turned.map((e) => e.join(',')).toSet(), spots.map((e) => e.join(',')).toSet(), reason: d.key);
      }
    });

    test('an unknown level falls back to Normal', () {
      expect(PenDifficulty.fromKey(null), PenDifficulty.normal);
      expect(PenDifficulty.fromKey('???'), PenDifficulty.normal);
      expect(PenDifficulty.fromKey('hard'), PenDifficulty.hard);
    });
  });

  group('messages', () {
    test('a flick survives the trip over the channel', () {
      final m = PenMessage(type: PenMessageType.flick, from: 'u1', seq: 3, world: PenWorld.start().flicked(0, -1, 0.5), round: 2);
      final back = PenMessage.fromJson(m.toJson());
      expect(back, m);
    });

    test('a message survives the channel adding its own type and event fields', () {
      final m = PenMessage(type: PenMessageType.flick, from: 'u1', seq: 1, world: PenWorld.start().flicked(0, -1, 0.5));
      final delivered = {...m.toJson(), 'type': 'broadcast', 'event': 'pen'};
      expect(PenMessage.fromJson(delivered), m);
    });

    test('malformed messages are dropped', () {
      expect(PenMessage.fromJson({'kind': 'nope', 'from': 'u1'}), isNull);
      expect(PenMessage.fromJson({'kind': 'flick', 'from': 'u1'}), isNull, reason: 'a flick needs both pens');
      expect(PenMessage.fromJson({'kind': 'hello'}), isNull);
      expect(PenMessage.fromJson({'kind': 'hello', 'from': 'u1'})?.type, PenMessageType.hello);
    });
  });
}
