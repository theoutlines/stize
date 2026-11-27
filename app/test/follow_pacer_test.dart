import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/follow_camera.dart';

void main() {
  final t0 = DateTime(2026, 11, 27, 2);
  Duration ms(int n) => Duration(milliseconds: n);

  test('without a flight, follow tracks at once', () {
    final p = FollowPacer()..start(t0, afterFlight: false);
    expect(p.readyAt(t0), isTrue);
  });

  test('after a flight it waits for the flight, or for the fallback', () {
    final p = FollowPacer()..start(t0, afterFlight: true);
    expect(p.readyAt(t0.add(ms(500))), isFalse);
    expect(
      p.readyAt(t0.add(ms(1200))),
      isTrue,
      reason: 'flight never reported',
    );
    final q = FollowPacer()..start(t0, afterFlight: true);
    q.engage();
    expect(q.readyAt(t0.add(ms(10))), isTrue);
  });

  test('the camera moves at most every 66 ms', () {
    final p = FollowPacer()..start(t0, afterFlight: false);
    expect(p.moveDueAt(t0), isTrue);
    expect(p.moveDueAt(t0.add(ms(30))), isFalse);
    expect(p.moveDueAt(t0.add(ms(66))), isTrue);
  });

  test('a restart forgets the last move; stop disengages', () {
    final p = FollowPacer()..start(t0, afterFlight: false);
    p.moveDueAt(t0);
    p.start(t0.add(ms(10)), afterFlight: false);
    expect(p.moveDueAt(t0.add(ms(20))), isTrue);
    p.stop();
    expect(p.engaged, isFalse);
  });
}
