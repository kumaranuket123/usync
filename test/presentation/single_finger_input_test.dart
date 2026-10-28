import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usync/presentation/features/canvas/widgets/single_finger_input.dart';

void main() {
  late List<String> log;

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: SingleFingerInput(
          onStart: (o) => log.add('start ${o.dx.toInt()},${o.dy.toInt()}'),
          onUpdate: (o) => log.add('move ${o.dx.toInt()},${o.dy.toInt()}'),
          onEnd: () => log.add('end'),
          child: const SizedBox.expand(),
        ),
      ));

  setUp(() => log = []);

  testWidgets('one finger draws from the first touch, with no delay before the stroke starts', (tester) async {
    await pump(tester);
    final g = await tester.startGesture(const Offset(10, 10));
    expect(log, ['start 10,10'], reason: 'no touch slop: the beginning of the stroke is kept');
    await g.moveTo(const Offset(12, 14));
    await g.up();
    expect(log, ['start 10,10', 'move 12,14', 'end']);
  });

  testWidgets('a second finger or a resting palm never joins or jumps the stroke', (tester) async {
    await pump(tester);
    final first = await tester.startGesture(const Offset(10, 10), pointer: 1);
    final palm = await tester.startGesture(const Offset(200, 300), pointer: 2);
    await palm.moveTo(const Offset(210, 310));
    await first.moveTo(const Offset(20, 20));
    await palm.up();
    expect(log, ['start 10,10', 'move 20,20'], reason: 'the palm changed nothing and its lift did not end the stroke');
    await first.up();
    expect(log.last, 'end');
    expect(log.where((l) => l == 'end'), hasLength(1));
  });

  testWidgets('after the stroke ends, the next touch starts a new one', (tester) async {
    await pump(tester);
    await (await tester.startGesture(const Offset(1, 1))).up();
    await (await tester.startGesture(const Offset(5, 5))).up();
    expect(log, ['start 1,1', 'end', 'start 5,5', 'end']);
  });
}
