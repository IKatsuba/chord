import 'package:chord/session/elapsed.dart';
import 'package:test/test.dart';

void main() {
  test('elapsed time reads as seconds, then minutes, then hours', () {
    for (final (ms, expected) in [
      (-5, '0s'),
      (0, '0s'),
      (12999, '12s'),
      (59000, '59s'),
      (60000, '1m 0s'),
      (65000, '1m 5s'),
      (3600000, '1h 0m'),
      (3725000, '1h 2m'),
    ]) {
      expect(formatElapsed(ms), expected);
    }
  });
  group('tester U10 elapsed rollover boundaries', () {
    test('floors fractional milliseconds and clamps clock reversal', () {
      for (final (ms, expected) in [
        (-100000, '0s'),
        (-0.1, '0s'),
        (999.9, '0s'),
        (1000.1, '1s'),
        (59999.9, '59s'),
        (60000.1, '1m 0s'),
        (3599999.9, '59m 59s'),
        (3600000.1, '1h 0m'),
        (86400000, '24h 0m'),
      ]) {
        expect(formatElapsed(ms), expected, reason: '$ms ms');
      }
    });
  });
}
