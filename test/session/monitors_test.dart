import 'package:chord/session/monitors.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

void main() {
  test('a line is stripped of escapes and cut past 1,000 characters', () {
    expect(eventLine('\x1b[31mERROR\x1b[0m boom'), 'ERROR boom');
    expect(eventLine('x' * 1000), 'x' * 1000);
    expect(eventLine('é' * 1003), '${'é' * 1000}… (+3 characters)');
    // A character beyond the BMP counts once, as the original's spread does.
    expect(eventLine('😀' * 1001), '${'😀' * 1000}… (+1 characters)');
  });

  test('an event carries the first 100 lines or 16 KiB, and counts the '
      'rest', () {
    final lines = [for (var i = 0; i < 340; i++) 'line $i'];
    final event = withLines(noLines, lines);
    expect(event.lines.length, 100);
    expect(event.dropped, 240);
    expect(
      eventText(event).split('\n').last,
      '… 240 more lines not delivered (an event carries at most 100)',
    );
    expect(
      eventText(withLines(noLines, [], 1234)),
      '… 1,234 more lines not delivered (an event carries at most 100)',
    );
    expect(
      eventText(withLines(noLines, [], 1)),
      '… 1 more line not delivered (an event carries at most 100)',
    );

    final wide = withLines(noLines, List.filled(20, 'y' * 1000));
    // 16 lines of 1,001 bytes fit in 16 KiB; the 17th does not.
    expect([wide.lines.length, wide.dropped], [16, 4]);

    // Once one is left out, later short ones are too: what goes is unbroken.
    final after = withLines(wide, ['short'], 2);
    expect([after.lines.length, after.dropped], [16, 7]);
    expect(
      eventText(withLines(noLines, ['a', 'b']), 'Exited with code 0 after 1s.'),
      'a\nb\nExited with code 0 after 1s.',
    );
  });

  test('a flood is more than 1,000 lines or 256 KiB within any 10 s', () {
    final lines = FloodWatch();
    for (var i = 0; i < 1000; i++) {
      expect(lines.add(i, 10), isNull);
    }
    expect(lines.add(1000, 10), FloodBy.lines);

    // 1,000 lines a little over 10 s apart are no flood: the window slides.
    final slow = FloodWatch();
    for (var i = 0; i < 2000; i++) {
      expect(slow.add(i * 11, 10), isNull);
    }

    final bytes = FloodWatch();
    expect(bytes.add(0, 200 * 1024), isNull);
    expect(bytes.add(9999, 57 * 1024), FloodBy.bytes);
    expect(FloodWatch().add(0, 300 * 1024), FloodBy.bytes);

    final slid = FloodWatch()..add(0, 200 * 1024);
    expect(slid.add(10000, 200 * 1024), isNull);
  });

  test('what monitor is asked is refused, never clamped, outside its '
      'bounds', () {
    MonitorArgs asked({String description = 'log', num? timeoutMs}) => (
      command: 'tail -f log',
      description: description,
      timeoutMs: timeoutMs,
    );
    expect(monitorRefusal(asked(), 7), isNull);
    expect(
      monitorRefusal(asked(), 8),
      'This session has 8 monitors running; stop_monitor one first',
    );
    for (final description in ['', 'two\nlines', 'x' * 61]) {
      expect(
        monitorRefusal(asked(description: description), 0),
        'description is at most 60 characters on one line; it is shown on '
        'every event',
      );
    }
    expect(monitorRefusal(asked(description: 'é' * 60), 0), isNull);
    for (final timeoutMs in [999, 3600001, 1500.5]) {
      expect(
        monitorRefusal(asked(timeoutMs: timeoutMs), 0),
        'timeout_ms is between 1000 and 3600000 (1h)',
      );
    }
    expect(monitorRefusal(asked(timeoutMs: 1000), 0), isNull);
    expect(monitorRefusal(asked(timeoutMs: 3600000), 0), isNull);
    expect(
      monitorRefusal((command: '  ', description: 'log', timeoutMs: null), 0),
      'command is empty',
    );
  });

  test('each end has its word and its sentence', () {
    String said(MonitorEnd end, [int ran = 363000]) =>
        '${endWord(end)} | ${endSentence(end, ran)}';
    expect(
      said(const MonitorExited(0)),
      'exit code 0 | Exited with code 0 after 6m 3s.',
    );
    expect(
      said(const MonitorExited(127), 0),
      'exit code 127 | Exited with code 127 (command not found) after 0s.',
    );
    expect(
      said(const MonitorExited(126), 0),
      'exit code 126 | Exited with code 126 (not executable) after 0s.',
    );
    expect(
      said(const MonitorKilled('SIGKILL')),
      'killed by SIGKILL | Killed by SIGKILL after 6m 3s.',
    );
    expect(
      said(const MonitorTimedOut(600000)),
      'timed out | Timed out after 10m (timeout_ms 600000); chord stopped it.',
    );
    expect(
      said(const MonitorStopped(), 252000),
      'stopped | The person stopped it after 4m 12s.',
    );
    expect(
      said(const MonitorFlooded(FloodBy.lines)),
      'flooded | chord stopped it: 1,000 lines in 10s is more than a monitor '
      'may print. Filter its output (grep --line-buffered) and start it '
      'again.',
    );
    expect(
      endSentence(const MonitorFlooded(FloodBy.bytes), 0).split(':')[1],
      ' 256 KiB in 10s is more than a monitor may print. Filter its output '
      '(grep --line-buffered) and start it again.',
    );
    expect(
      [timeoutWords(1000), timeoutWords(90000), timeoutWords(3600000)],
      ['1s', '1m 30s', '1h'],
    );
  });

  test('a resumed past names the monitors it left running, to the person '
      'and to its agent', () {
    expect(
      leftRunningLine([(id: 'm1', description: 'watch')]),
      'watch was running when this session was left and is not restarted',
    );
    expect(
      leftRunningLine([
        (id: 'm1', description: 'a'),
        (id: 'm2', description: 'b'),
        (id: 'm3', description: 'c'),
      ]),
      'a, b and c were running when this session was left and are not '
      'restarted',
    );
    expect(
      leftStoppedNote([
        (id: 'm2', description: 'watch'),
        (id: 'm4', description: 'heartbeat'),
      ]),
      'Your monitors m2 (watch) and m4 (heartbeat) were running when this '
      'session was left. chord stopped them then, and nothing restarts '
      'them; start them again with monitor if you still need them.',
    );
    expect(
      leftStoppedNote([(id: 'm1', description: 'watch')]),
      'Your monitor m1 (watch) was running when this session was left. '
      'chord stopped it then, and nothing restarts it; start it again with '
      'monitor if you still need it.',
    );
  });

  group('CTUI-36 tester: monitor helper boundaries', () {
    test('UTF-8 bytes include newlines and retain exactly the byte cap', () {
      final exact = withLines(noLines, ['😀' * 4095 + 'abc']);
      expect(exact.bytes, eventBytes);
      expect(exact.dropped, 0);
      final overflow = withLines(exact, ['']);
      expect(overflow.lines, exact.lines);
      expect(overflow.bytes, eventBytes);
      expect(overflow.dropped, 1);
      expect(exact.dropped, 0);
      expect(noLines.lines, isEmpty);

      final tooLarge = withLines(noLines, ['😀' * 4096, 'small']);
      expect(tooLarge.lines, isEmpty);
      expect(tooLarge.bytes, 0);
      expect(tooLarge.dropped, 2);
    });

    test(
      'repeated batches retain only an unbroken prefix and count losses',
      () {
        var event = noLines;
        for (var i = 0; i < 1000; i++) {
          event = withLines(event, ['$i']);
        }
        expect(event.lines, [for (var i = 0; i < 100; i++) '$i']);
        expect(event.dropped, 900);
        final priorLoss = withLines(noLines, ['first'], 2);
        expect(withLines(priorLoss, ['later']).dropped, 3);
        expect(withLines(priorLoss, ['later']).lines, ['first']);
        expect(eventText(noLines), '');
        expect(eventText(noLines, 'ended'), 'ended');
        expect(
          eventText(priorLoss, 'ended'),
          'first\n… 2 more lines not delivered '
          '(an event carries at most 100)\nended',
        );
      },
    );

    test('line limits count code points after removing terminal escapes', () {
      expect(eventLine(''), '');
      expect(eventLine('\x1b[31m\x1b[0m'), '');
      expect(
        eventLine('${'界' * 999}\x1b[31m😀\x1b[0me\u0301'),
        '${'界' * 999}😀… (+2 characters)',
      );
      expect(
        eventLine('${'x' * 999}e\u0301'),
        '${'x' * 999}e… (+1 characters)',
      );
      expect(
        eventLine('\x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\'),
        'link',
      );
    });

    test('flood thresholds are strict and expired bytes leave the window', () {
      final bytes = FloodWatch();
      expect(bytes.add(0, floodBytes), isNull);
      expect(bytes.add(floodMs - 1, 1), FloodBy.bytes);
      expect(bytes.add(floodMs, floodBytes - 1), isNull);
      expect(bytes.add(2 * floodMs, floodBytes), isNull);
      final both = FloodWatch();
      for (var i = 0; i < floodLines; i++) {
        expect(both.add(0, 1), isNull);
      }
      expect(both.add(0, floodBytes), FloodBy.lines);
      expect(both.add(floodMs, 1), isNull);
    });

    test(
      'sliding history compaction preserves recent entries and byte totals',
      () {
        final watch = FloodWatch();
        for (var i = 0; i < 5000; i++) {
          expect(watch.add(i * floodMs, 1), isNull);
        }
        expect(watch.add(4999 * floodMs, floodBytes - 1), isNull);
        expect(watch.add(4999 * floodMs, 1), FloodBy.bytes);
        expect(watch.add(5000 * floodMs, floodBytes), isNull);
      },
    );

    test(
      'descriptions count code points after trim and refusals have priority',
      () {
        MonitorArgs args(String description, {String command = 'watch'}) =>
            (command: command, description: description, timeoutMs: null);
        expect(monitorRefusal(args('  ${'😀' * 60}\n'), 0), isNull);
        expect(monitorRefusal(args('e\u0301' * 30), 0), isNull);
        for (final description in ['😀' * 61, 'e\u0301' * 31, 'a\rb']) {
          expect(
            monitorRefusal(args(description), 0),
            startsWith('description'),
          );
        }
        expect(
          monitorRefusal(args('', command: ''), 8),
          startsWith('This session'),
        );
        expect(
          monitorRefusal(args('', command: ''), 0),
          startsWith('description'),
        );
        expect(
          monitorRefusal(args('ok', command: '\t\n '), 0),
          'command is empty',
        );
      },
    );
  });
}
