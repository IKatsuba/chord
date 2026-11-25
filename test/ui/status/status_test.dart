import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/status/status.dart';
import 'package:chord_tui/chord_tui.dart' show cellWidth;
import 'package:test/test.dart';

String text(StatusFacts facts, int width) {
  final view = statusLine(facts, width);
  return [
    view.left.map((p) => p.text).join(' '),
    view.right.map((p) => p.text).join(statusSeparator),
  ].where((s) => s.isNotEmpty).join('  ');
}

void main() {
  const usage = Usage(120000, 200000);
  const facts = StatusFacts(
    model: 'Fake Large with a 1M context window',
    effort: 'high',
    mode: 'plan',
    usage: usage,
  );
  test('context is the complement of free share rounded down and bounded', () {
    for (final (used, size, expected) in [
      (120000, 200000, 60),
      (1200, 200000, 1),
      (0, 200000, 0),
      (199000, 200000, 100),
      (300, 200, 100),
      (0, 0, 100),
      (-1, 200, 0),
    ]) {
      expect(contextUsed(Usage(used, size)), expected);
    }
  });
  test('known modes retain wording and unknown modes use reported names', () {
    expect(modePart('default'), isNull);
    expect(modePart('plan')!.text, '⏸ plan mode on');
    expect(modePart('acceptEdits')!.tone, StatusTone.edits);
    expect(modePart('auto')!.text, '⏵⏵ auto mode on');
    expect(modePart('bypassPermissions')!.tone, StatusTone.bypass);
    expect(modePart('read-only', 'Read Only')!.text, '⏵⏵ read only mode on');
    expect(modePart('review')!.tone, StatusTone.plain);
  });
  test('full status shortens words, drops effort, then cuts the model', () {
    expect(
      text(facts, 120),
      '⏸ plan mode on  Fake Large with a 1M context window · high effort · 60% context used',
    );
    const noEffort = StatusFacts(
      model: 'Fake Large with a 1M context window',
      mode: 'plan',
      usage: usage,
    );
    expect(
      text(noEffort, 70),
      '⏸ plan mode on  Fake Large with a 1M context window · 60% context used',
    );
    expect(
      text(noEffort, 50),
      '⏸ plan mode on  Fake Large with a 1M… · 60% used',
    );
    expect(text(noEffort, 30), '⏸ plan mode on  60% used');
    expect(text(noEffort, 20), '⏸ plan mode on');
    for (var width = 14; width <= 120; width++) {
      expect(cellWidth(text(facts, width)), lessThanOrEqualTo(width));
      expect(text(facts, width), startsWith('⏸ plan mode on'));
    }
  });
  test(
    'notices outrank modes and facts, and only reported facts are shown',
    () {
      const notice = StatusFacts(
        model: 'Fake Large with a 1M context window',
        mode: 'plan',
        notice: 'Press ctrl+c again to quit',
        usage: usage,
      );
      expect(text(notice, 36), 'Press ctrl+c again to quit  60% used');
      expect(text(notice, 30), 'Press ctrl+c again to quit');
      expect(text(const StatusFacts(), 80), '');
      expect(text(const StatusFacts(model: 'Fake'), 80), 'Fake');
      expect(text(const StatusFacts(usage: Usage(0, 0)), 80), '');
      expect(
        text(const StatusFacts(mode: 'default', usage: usage), 80),
        '60% context used',
      );
      expect(
        statusLine(
          const StatusFacts(usage: Usage(160000, 200000)),
          80,
        ).right.single.tone,
        StatusTone.plain,
      );
      expect(
        statusLine(
          const StatusFacts(usage: Usage(161000, 200000)),
          80,
        ).right.single.tone,
        StatusTone.low,
      );
    },
  );
  test(
    'working, interrupting and permission waits use original elapsed time',
    () {
      expect(workingLine(const Idle(), 12000), isNull);
      final working = workingLine(const Working('t', 1000), 13999)!;
      expect(
        (working.label, working.detail),
        ('Working…', '12s · esc to interrupt'),
      );
      expect(
        workingLine(const Working('t', 1000), 13999, cancelKey: null)!.detail,
        '12s',
      );
      expect(
        workingLine(const Cancelling('t', 1000, 9000), 13999)!.detail,
        '12s',
      );
      final permission = workingLine(
        const AwaitingPermission('t', 1000, [
          PermissionWait('ask', at: 10000, deadlineAt: 310000),
        ]),
        14000,
      )!;
      expect(
        (permission.label, permission.detail),
        ('Waiting for permission…', '4s · denied in 4m 56s'),
      );
      expect(
        workingLine(const AwaitingPermission('t', 1000, []), 14000)!.detail,
        '13s',
      );
    },
  );
  test('spinner lights three marks then rests, with gradient or one tone', () {
    for (var step = 0; step < 8; step++) {
      final marks = spinnerMarks(step);
      expect(marks.map((m) => m.dim), [
        for (var i = 0; i < 3; i++) i != step % 4,
      ]);
      expect(marks.map((m) => m.colour), [null, null, null]);
      final colored = spinnerMarks(step, const MarkTones(tone: '#123456'));
      expect(colored.every((m) => m.colour == '#123456'), isTrue);
      final gradient = spinnerMarks(
        step,
        const MarkTones(stops: ['#ffffff', '#888888', '#000000']),
      );
      expect(gradient.every((m) => !m.dim), isTrue);
      expect(gradient.map((m) => m.colour), [
        for (var i = 0; i < 3; i++) i == step % 4 ? '#ffffff' : '#000000',
      ]);
    }
  });
  group('tester U10 status selection boundaries', () {
    test(
      'original Unicode model cuts preserve notice and usage cell budgets',
      () {
        const model = '界e\u0301👩‍💻 model with a very long descriptive name';
        const facts = StatusFacts(
          model: model,
          notice: 'Permission waits',
          usage: Usage(120000, 200000),
        );
        for (var width = 32; width <= 80; width++) {
          final view = statusLine(facts, width);
          final shown = text(facts, width);
          expect(shown, startsWith('Permission waits'));
          expect(cellWidth(shown), lessThanOrEqualTo(width));
          for (final part in view.right.where((p) => p.text.contains('…'))) {
            expect(
              model,
              startsWith(part.text.substring(0, part.text.length - 1)),
            );
            expect(part.text, isNot(contains('�')));
            expect(part.text, isNot(endsWith('\u200d…')));
          }
        }
      },
    );

    test(
      'authoritative permission countdown expires at zero without changing turn',
      () {
        const turn = AwaitingPermission('t', 1000, [
          PermissionWait('first', at: 10000, deadlineAt: 310000),
          PermissionWait('second', at: 20000, deadlineAt: 999999),
        ]);
        expect(workingLine(turn, 400000)!.detail, '6m 30s · denied in 0s');
        expect(workingLine(turn, 9000)!.detail, '0s · denied in 5m 1s');
        expect(
          workingLine(const Cancelling('t', 1000, 9000), 61000)!.detail,
          '1m 0s',
        );
        expect(
          workingLine(
            const Working('t', 1000),
            61000,
            cancelKey: 'ctrl+x',
          )!.detail,
          '1m 0s · ctrl+x to interrupt',
        );
        expect(turn.permissions.first.deadlineAt, 310000);
      },
    );

    test(
      'context uses fractional reported numbers and low tone only above eighty',
      () {
        for (final (used, size, percent) in [
          (0.1, 100, 1),
          (80, 100, 80),
          (80.01, 100, 81),
          (100.1, 100, 100),
          (-0.1, 100, 0),
        ]) {
          final usage = Usage(used, size);
          expect(contextUsed(usage), percent);
          expect(
            statusLine(StatusFacts(usage: usage), 80).right.single.tone,
            percent > 80 ? StatusTone.low : StatusTone.plain,
          );
        }
        expect(
          statusLine(const StatusFacts(usage: Usage(50, -1)), 80).right,
          isEmpty,
        );
      },
    );

    test('tiny widths retain notice or mode for renderer clipping', () {
      for (final width in [0, 1, 5, 13]) {
        final mode = statusLine(
          const StatusFacts(
            mode: 'plan',
            model: 'model',
            effort: 'high',
            usage: Usage(5, 10),
          ),
          width,
        );
        expect(mode.left.single.text, '⏸ plan mode on');
        expect(mode.right, isEmpty);
        final notice = statusLine(
          const StatusFacts(
            notice: 'Keep this notice',
            mode: 'plan',
            usage: Usage(5, 10),
          ),
          width,
        );
        expect(notice.left.single.text, 'Keep this notice');
        expect(notice.right, isEmpty);
      }
    });
  });
  test('a context chord worked out is marked, and a window nobody knows says '
      'nothing', () {
    const plain = StatusFacts(
      model: 'Fake Large with a 1M context window',
      mode: 'default',
      usage: Usage(120000, 200000, estimated: ['size']),
    );
    expect(
      text(plain, 116),
      'Fake Large with a 1M context window · ~60% context used',
    );
    // An estimated cost alone leaves the agent's context unmarked.
    expect(
      text(
        const StatusFacts(
          model: 'Fake Large with a 1M context window',
          mode: 'default',
          usage: Usage(120000, 200000, estimated: ['cost']),
        ),
        116,
      ),
      'Fake Large with a 1M context window · 60% context used',
    );
    expect(
      text(
        const StatusFacts(
          model: 'Fake Large with a 1M context window',
          mode: 'default',
          usage: Usage(10, 0),
        ),
        116,
      ),
      'Fake Large with a 1M context window',
    );
  });
}
