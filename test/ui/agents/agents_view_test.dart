import 'package:chord/notify.dart';
import 'package:chord/session/waits.dart';
import 'package:chord/ui/agents/agents.dart';
import 'package:chord/ui/agents/agents_view.dart';
import 'package:chord/ui/theme/theme.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'agents_teams_test.dart' as teams;

const large = 'Fake Large with a 1M context window';
final dark = palettes['dark']!;

/// A row as the fake's session draws it: `fake`, its model and effort.
AgentRow row(
  String name,
  int key, {
  int? colour,
  String runtime = 'fake',
  String? model = large,
  String? effort,
  bool picked = false,
  bool failed = false,
  AgentWait wait = const AgentWait(),
}) => AgentRow(
  key: key,
  name: name,
  runtime: runtime,
  model: model,
  effort: effort,
  colour: colour,
  picked: picked,
  failed: failed,
  wait: wait,
);

Asking permission(num since) => (on: const PermissionAsk(), since: since);

/// The captured moment of `bun dev chord --fake --qa agents`: main and
/// parser idle, docs asking, at [now].
List<AgentRow> moment(
  int now, {
  required int idleMain,
  required int idleParser,
  required int asking,
  bool seen = false,
  String picked = 'main',
}) => [
  row(
    'main',
    1,
    effort: 'medium',
    picked: picked == 'main',
    wait: AgentWait(stopped: now - idleMain * 1000),
  ),
  row(
    'parser',
    2,
    colour: 0,
    model: 'Fake Small',
    effort: 'medium',
    picked: picked == 'parser',
    wait: AgentWait(
      stopped: now - idleParser * 1000,
      unseen: seen ? null : Unseen(UnseenKind.replied, since: now),
    ),
  ),
  row(
    'docs',
    3,
    colour: 1,
    effort: 'medium',
    picked: picked == 'docs',
    wait: AgentWait(
      asking: permission(now - asking * 1000),
      unseen: seen
          ? null
          : Unseen(UnseenKind.message, from: '@main', since: now),
    ),
  ),
];

/// The window's last rows: room above, the list under it, as it stands
/// under the status line.
Widget bottom(Widget list) => Column(
  children: [
    const Expanded(child: SizedBox()),
    list,
  ],
);

/// Runs [body] on fake time from a fixed moment, as the original's tests
/// set the system time; every pump is driven to its end.
void onFakeTime(
  void Function(
    FakeAsync async,
    WidgetTester t,
    void Function(Future<void>) draw,
  )
  body,
) {
  fakeAsync((async) {
    final t = WidgetTester();
    void draw(Future<void> future) {
      var done = false;
      future.then((_) => done = true);
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(done, isTrue);
    }

    try {
      body(async, t, draw);
    } finally {
      t.dispose();
      async.flushMicrotasks();
    }
    expect(AgentsClock.running, isFalse, reason: 'released on dispose');
  }, initialTime: DateTime.utc(2026, 10, 21, 12));
}

int nowMs() => clock.now().millisecondsSinceEpoch;

/// The column of [text] on row [y] of the screen.
int at(Screen screen, int y, String text) {
  final x = screen.lines[y].indexOf(text);
  expect(x, isNot(-1), reason: '$text on row $y');
  return x;
}

/// Every cell of [text] on row [y] carries [style]'s colour and attributes.
void styled(Screen screen, int y, String text, Style style) {
  final from = at(screen, y, text);
  for (var x = from; x < from + text.length; x++) {
    if (screen.charAt(x, y) == ' ') continue;
    final cell = screen.styleAt(x, y);
    expect(
      (cell.fg, cell.isBold, cell.isDim),
      (style.fg, style.isBold, style.isDim),
      reason: '"${screen.charAt(x, y)}" of "$text" at $x,$y',
    );
  }
}

Color fg(String? colour) => colorOf(colour!);

void main() {
  group('CTUI-37 tester: keyed team list lifecycle', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'keyed folded list resizes and releases its live clock at $size',
        (t) async {
          final baseline = AgentsClock.subscribers;
          Widget list(String key, bool focused) => AgentsList(
            key: ValueKey(key),
            rows: listRows(teams.team(focused ? 'tester' : 'main'), limit: 4),
            limit: 8,
            focused: focused,
            palette: dark,
          );
          await t.pumpWidget(list('first', false), size: size);
          expect(AgentsClock.subscribers, baseline + 1);
          await t.resize(const Size(0, 1));
          await t.resize(const Size(1, 1));
          await t.pumpWidget(list('second', true), size: size);
          expect(AgentsClock.subscribers, baseline + 1);
          expect(t.screen.lines.join('\n'), contains('❯ ├─ tester'));
          await t.pumpWidget(const SizedBox(), size: size);
          expect(AgentsClock.subscribers, baseline);
          if (baseline == 0) expect(AgentsClock.running, isFalse);
        },
      );
    }
  });
  group('tester CTUI-124: folded count across focus and resize', () {
    test('hidden rows on both sides keep their count below the picked row', () {
      onFakeTime((async, t, draw) {
        Widget list(bool focused, int picked) => AgentsList(
          rows: [
            for (var key = 0; key < 9; key++)
              row('child-$key', key, model: null, picked: key == picked),
          ],
          limit: 4,
          focused: focused,
          palette: dark,
        );
        for (final size in const [Size(120, 40), Size(80, 24)]) {
          for (final picked in [4, 8]) {
            draw(t.pumpWidget(list(true, picked), size: size));
            void check() {
              final lines = t.screen.lines
                  .where((line) => line.isNotEmpty)
                  .toList();
              expect(lines, hasLength(4));
              expect(lines[2], startsWith('  ❯ child-$picked '));
              expect(lines.last, '    … +6 more');
              expect(lines.first, isNot(contains('child-0')));
              styled(t.screen, 3, '… +6 more', const Style(dim: true));
              expect(AgentsClock.subscribers, 1);
            }

            check();
            draw(t.resize(const Size(1, 1)));
            draw(t.resize(size));
            check();
            draw(t.pumpWidget(list(false, picked), size: size));
            expect(t.screen.lines[3], '    … +6 more');
            expect(t.screen.lines[0], contains('child-0'));
            draw(t.pumpWidget(list(true, picked), size: size));
            check();
            async.elapse(const Duration(seconds: 1));
            draw(t.pump());
            check();
          }
        }
        draw(t.pumpWidget(const SizedBox()));
        expect(AgentsClock.subscribers, 0);
        expect(async.periodicTimerCount, 0);
      });
    });
  });
  testerAgentsWidgetBoundaries();
  group("the original's captures (bun dev chord --fake --qa agents)", () {
    // Prompt holding the keys, a child asking.
    final asked = {
      const Size(120, 40): [
        '    main    fake · $large · medium  ◦ idle 5s',
        '    parser  fake · Fake Small · medium                           '
            '◦ idle 7s        ✓ new reply',
        '    docs    fake · $large · medium  ● permission 8s  ← new message',
      ],
      const Size(80, 24): [
        '    main    fake  ◦ idle 5s',
        '    parser  fake  ◦ idle 7s        ✓ new reply',
        '    docs    fake  ● permission 8s  ← new message',
      ],
    };
    for (final MapEntry(key: size, value: captured) in asked.entries) {
      for (final colour in [true, false]) {
        test('a child asking at ${size.width}x${size.height}'
            '${colour ? '' : ', without colour'}', () {
          onFakeTime((async, t, draw) {
            final palette = paletteOf('dark', colour);
            draw(
              t.pumpWidget(
                bottom(
                  AgentsList(
                    rows: moment(
                      nowMs(),
                      idleMain: 5,
                      idleParser: 7,
                      asking: 8,
                    ),
                    limit: agentsRowLimit(size.height),
                    focused: false,
                    palette: palette,
                  ),
                ),
                size: size,
              ),
            );
            final s = t.screen;
            final top = size.height - 3;
            expect(s.lines.sublist(top), captured);
            expect(s.lines.sublist(0, top).every((l) => l.isEmpty), isTrue);
            Style c(String? hex, {bool bold = false, bool dim = false}) =>
                Style(fg: colour ? fg(hex) : null, bold: bold, dim: dim);
            const dimmed = Style(dim: true);
            // main is picked, in the text's own colour; children in theirs.
            styled(s, top, 'main', const Style(bold: true));
            styled(s, top + 1, 'parser', c(dark.agents![0]));
            styled(s, top + 2, 'docs', c(dark.agents![1]));
            // The gutter and padding are plain cells.
            for (var x = 0; x < 4; x++) {
              expect(s.styleAt(x, top), Style.plain);
            }
            for (var y = top; y < top + 3; y++) {
              styled(s, y, 'fake', dimmed);
            }
            if (size.width == 120) {
              styled(s, top, '$large · medium', dimmed);
              styled(s, top + 1, 'Fake Small · medium', dimmed);
            }
            styled(s, top, '◦ idle 5s', dimmed);
            styled(s, top + 1, '◦ idle 7s', dimmed);
            styled(s, top + 1, '✓ new reply', dimmed);
            styled(s, top + 2, '● permission 8s', c(dark.warning));
            styled(s, top + 2, '← new message', dimmed);
            if (!colour) {
              for (var y = 0; y < size.height; y++) {
                for (var x = 0; x < size.width; x++) {
                  expect(s.styleAt(x, y).fg, isNull, reason: '$x,$y');
                }
              }
            }
          });
        });
      }
    }

    // ↓ from an empty prompt: the list has the keys, main picked.
    final focusedMain = {
      const Size(120, 40): [
        '  ❯ main    fake · $large · medium  ◦ idle 11s',
        '    parser  fake · Fake Small · medium                           '
            '◦ idle 13s        ✓ new reply',
        '    docs    fake · $large · medium  ● permission 14s  ← new message',
      ],
      const Size(80, 24): [
        '  ❯ main    fake  ◦ idle 11s',
        '    parser  fake  ◦ idle 13s        ✓ new reply',
        '    docs    fake  ● permission 14s  ← new message',
      ],
    };
    for (final MapEntry(key: size, value: captured) in focusedMain.entries) {
      test('the list holding the keys at ${size.width}x${size.height}', () {
        onFakeTime((async, t, draw) {
          draw(
            t.pumpWidget(
              bottom(
                AgentsList(
                  rows: moment(
                    nowMs(),
                    idleMain: 11,
                    idleParser: 13,
                    asking: 14,
                  ),
                  limit: agentsRowLimit(size.height),
                  focused: true,
                  palette: dark,
                ),
              ),
              size: size,
            ),
          );
          final top = size.height - 3;
          expect(t.screen.lines.sublist(top), captured);
          styled(t.screen, top, '❯', Style(fg: fg(dark.permission)));
          styled(t.screen, top, 'main', const Style(bold: true));
        });
      });
    }

    for (final size in const [Size(80, 24), Size(120, 40)]) {
      test('docs picked at ${size.width}x${size.height}: its marks seen, '
          'the model back', () {
        onFakeTime((async, t, draw) {
          draw(
            t.pumpWidget(
              bottom(
                AgentsList(
                  rows: moment(
                    nowMs(),
                    idleMain: 13,
                    idleParser: 15,
                    asking: 16,
                    seen: true,
                    picked: 'docs',
                  ),
                  limit: agentsRowLimit(size.height),
                  focused: true,
                  palette: dark,
                ),
              ),
              size: size,
            ),
          );
          final s = t.screen;
          final top = size.height - 3;
          expect(
            s.lines.sublist(top),
            size.width == 80
                ? [
                    '    main    fake · $large  ◦ idle 13s',
                    '    parser  fake · Fake Small                           '
                        '◦ idle 15s',
                    '  ❯ docs    fake · $large  ● permission 16s',
                  ]
                : [
                    '    main    fake · $large · medium  ◦ idle 13s',
                    '    parser  fake · Fake Small · medium                  '
                        '         ◦ idle 15s',
                    '  ❯ docs    fake · $large · medium  ● permission 16s',
                  ],
          );
          styled(s, top + 2, '❯', Style(fg: fg(dark.permission)));
          styled(
            s,
            top + 2,
            'docs',
            Style(fg: fg(dark.agents![1]), bold: true),
          );
          styled(s, top, 'main', Style.plain);
          styled(s, top + 2, '● permission 16s', Style(fg: fg(dark.warning)));
        });
      });
    }
  });

  group('no list', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      test('without a child nothing is drawn and nothing counts, '
          '${size.width}x${size.height}', () {
        onFakeTime((async, t, draw) {
          final rows = ValueNotifier<List<AgentRow>>([
            row('main', 1, picked: true, wait: const AgentWait(working: 0)),
          ]);
          draw(
            t.pumpWidget(
              ListenableBuilder(
                listenable: rows,
                builder: (_) => bottom(
                  AgentsList(
                    rows: rows.value,
                    limit: 6,
                    focused: false,
                    palette: dark,
                  ),
                ),
              ),
              size: size,
            ),
          );
          expect(t.screen.text, isEmpty);
          expect(async.periodicTimerCount, 0);
          // A child opens: the list and its clock come.
          rows.value = [
            ...rows.value,
            row('parser', 2, colour: 0, wait: AgentWait(stopped: nowMs())),
          ];
          draw(t.pump());
          expect(t.screen, shows('parser'));
          expect(async.periodicTimerCount, 1);
          // It closes again: both go.
          rows.value = rows.value.sublist(0, 1);
          draw(t.pump());
          expect(t.screen.text, isEmpty);
          expect(async.periodicTimerCount, 0);
          rows.dispose();
        });
      });
    }
  });

  group('furniture', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      test('a drag across the list copies none of it, '
          '${size.width}x${size.height}', () {
        onFakeTime((async, t, draw) {
          final controller = SelectionController();
          final finalized = <SelectionValue>[];
          draw(
            t.pumpWidget(
              SelectionArea(
                controller: controller,
                selectionStyle: const Style(inverse: true),
                onSelectionFinalized: finalized.add,
                child: Column(
                  children: [
                    Text('the reply'),
                    const Expanded(child: SizedBox()),
                    AgentsList(
                      rows: moment(
                        nowMs(),
                        idleMain: 5,
                        idleParser: 7,
                        asking: 8,
                      ),
                      limit: agentsRowLimit(size.height),
                      focused: false,
                      palette: dark,
                    ),
                  ],
                ),
              ),
              size: size,
            ),
          );
          final top = size.height - 3;
          MouseEvent pointer(MouseEventKind kind, int x, int y) => MouseEvent(
            kind,
            position: Offset(x, y),
            button: MouseButton.primary,
          );
          void drag(Offset from, Offset to) {
            draw(t.mouse(pointer(MouseEventKind.press, from.x, from.y)));
            draw(t.mouse(pointer(MouseEventKind.move, to.x, to.y)));
            draw(t.mouse(pointer(MouseEventKind.release, to.x, to.y)));
          }

          // Over the list alone, from its first name to its last mark:
          // nothing.
          final last = t.screen.lines[size.height - 1].length - 1;
          drag(Offset(4, top), Offset(last, size.height - 1));
          expect(controller.snapshot()?.text ?? '', isEmpty);
          expect(finalized.every((value) => !value.hasText), isTrue);
          // From the reply down across the list: the reply alone.
          drag(const Offset(0, 0), Offset(size.width - 1, size.height - 1));
          expect(controller.snapshot()!.text.trim(), 'the reply');
          expect(controller.snapshot()!.text, isNot(contains('parser')));
          // From the list up onto the reply: the reply alone.
          drag(Offset(last, size.height - 1), const Offset(0, 0));
          expect(controller.snapshot()!.text.trim(), 'the reply');
          controller.dispose();
        });
      });
    }
  });

  group("the original's AgentsList cases", () {
    test(
      "a narrow list wraps a long name in its column and draws a state under "
      "its detail in the state's colour, cutting nothing (CHD-471)",
      () {
        onFakeTime((async, t, draw) {
          final now = nowMs();
          draw(
            t.pumpWidget(
              AgentsList(
                rows: [
                  row('main', 1, model: 'Fake', picked: true),
                  row(
                    'a-child-with-a-long-name',
                    2,
                    colour: 0,
                    model: 'Fake',
                    wait: AgentWait(asking: permission(now - 8000)),
                  ),
                ],
                limit: 6,
                focused: false,
                palette: dark,
              ),
              size: const Size(34, 8),
            ),
          );
          expect(t.screen.lines.where((line) => line.isNotEmpty), [
            '    main        fake  ◦ idle 0s',
            '    a-child-wi  fake',
            '    th-a-long-  ● permission 8s',
            '    name',
          ]);
          // #ffc107, the dark palette's warning, on the state under the
          // detail.
          expect(dark.warning, '#ffc107');
          styled(t.screen, 2, '● permission 8s', Style(fg: fg(dark.warning)));
          styled(t.screen, 2, 'th-a-long-', Style(fg: fg(dark.agents![0])));
        });
      },
    );

    test('a detail wider than the list on its own is drawn whole, wrapped '
        'under its start, nothing clipped (CHD-471)', () {
      onFakeTime((async, t, draw) {
        draw(
          t.pumpWidget(
            AgentsList(
              rows: [
                row('main', 1, model: null, picked: true),
                row(
                  'parser',
                  2,
                  runtime: 'a-runtime-named-past-the-line and more words',
                  model: null,
                ),
              ],
              limit: 9,
              focused: false,
              palette: dark,
            ),
            size: const Size(34, 8),
          ),
        );
        expect(t.screen.lines.where((line) => line.isNotEmpty), [
          '    main    fake  ◦ idle 0s',
          '    parser  a-runtime-named-past',
          '            -the-line and more',
          '            words',
          '            ◦ idle 0s',
        ]);
        styled(t.screen, 2, '-the-line and more', const Style(dim: true));
        styled(t.screen, 4, '◦ idle 0s', const Style(dim: true));
      });
    });

    test('a picked row taller than the list is drawn in the list’s lines and '
        'no more, ↑ and ↓ in the gutter (CHD-471)', () {
      const title =
          'Summarise the release notes for 0.56.0 from the commits since '
          '0.55.2, grouped by area, with a line for each user-facing change '
          'and a note for each breaking one, then draft the announcement.';
      final rows = [
        row('main', 1, model: null),
        row(title, 2, colour: 0, model: null, picked: true),
        row('docs', 3, colour: 1, model: null),
      ];
      for (final view in [
        null,
        const AgentsView(key: 2, width: 76, limit: 4, top: 3),
      ]) {
        onFakeTime((async, t, draw) {
          draw(
            t.pumpWidget(
              AgentsList(
                rows: rows,
                limit: 4,
                focused: true,
                palette: dark,
                view: view,
              ),
              size: const Size(80, 12),
            ),
          );
          final lines = [
            for (final line in t.screen.lines)
              if (line.isNotEmpty) line,
          ];
          expect(lines, hasLength(4));
          expect(lines.last, startsWith('  ↓ '));
          styled(t.screen, 3, '↓', const Style(dim: true));
          if (view != null) {
            expect(lines.first, startsWith('  ↑ '));
            styled(t.screen, 0, '↑', const Style(dim: true));
          }
        });
      }
    });

    // CTUI-124: `  … +N more` after the rows, also when the hidden rows sit
    // above the picked one (../chord/src/ui/agents/Agents.tsx:196-200), N
    // being every row not drawn (agentsLayout's `more: rows.length -
    // shown.length`, ../chord/src/ui/agents/agents.ts).
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      test('at ${size.width}x${size.height} the list folded above the picked '
          'last row ends in a dim … +N more counting them', () {
        final rows = [
          for (var key = 0; key < 9; key++)
            row(
              key == 0 ? 'main' : 'child-$key',
              key,
              model: null,
              picked: key == 8,
            ),
        ];
        final limit = agentsRowLimit(size.height.toInt());
        onFakeTime((async, t, draw) {
          draw(
            t.pumpWidget(
              AgentsList(
                rows: rows,
                limit: limit,
                focused: true,
                palette: dark,
              ),
              size: size,
            ),
          );
          final lines = [
            for (final line in t.screen.lines)
              if (line.isNotEmpty) line,
          ];
          final hidden = rows.length - (limit - 1);
          expect(lines, hasLength(limit));
          expect(lines[lines.length - 2], startsWith('  ❯ child-8 '));
          expect(lines.last, '    … +$hidden more');
          expect(lines.any((line) => line.contains('main')), isFalse);
          styled(
            t.screen,
            limit - 1,
            '… +$hidden more',
            const Style(dim: true),
          );
        });
      });
    }

    group('working in the accent with dim, a new reply dim, in each theme '
        '(CHD-483)', () {
      // The 16-colour themes' accent is the warning's yellow, so working
      // takes green there.
      final cases = [
        ('dark', true, RgbColor(71, 231, 165)),
        ('light', true, RgbColor(20, 125, 85)),
        ('dark-daltonized', true, RgbColor(71, 231, 165)),
        ('dark-ansi', true, Colors.brightGreen),
        ('light-ansi', true, Colors.green),
        // Without colour, dim alone.
        ('dark', false, null),
      ];
      for (final (theme, colour, working) in cases) {
        test('$theme${colour ? '' : ' without colour'}', () {
          onFakeTime((async, t, draw) {
            final now = nowMs();
            draw(
              t.pumpWidget(
                AgentsList(
                  rows: [
                    row(
                      'main',
                      1,
                      model: 'Fake',
                      picked: true,
                      wait: AgentWait(working: now - 9000),
                    ),
                    row(
                      'parser',
                      4,
                      colour: 0,
                      model: 'Fake',
                      wait: AgentWait(
                        stopped: now - 4000,
                        unseen: Unseen(UnseenKind.replied, since: now),
                      ),
                    ),
                  ],
                  limit: 6,
                  focused: false,
                  palette: paletteOf(theme, colour),
                ),
                size: const Size(100, 8),
              ),
            );
            styled(t.screen, 0, '✻ working 9s', Style(fg: working, dim: true));
            styled(t.screen, 1, '✓ new reply', const Style(dim: true));
          });
        });
      }
    });

    group('neighbouring states keep separate styles (CHD-483 V1)', () {
      for (final columns in [80, 120]) {
        for (final (theme, enabled) in [
          ('dark', true),
          ('light', true),
          ('light-daltonized', true),
          ('dark-ansi', true),
          ('light-ansi', true),
          ('light', false),
        ]) {
          test('$theme, colour $enabled, at $columns columns', () {
            onFakeTime((async, t, draw) {
              final now = nowMs();
              final palette = paletteOf(theme, enabled);
              draw(
                t.pumpWidget(
                  AgentsList(
                    rows: [
                      row(
                        '解析担当',
                        1,
                        model: 'Fake',
                        picked: true,
                        wait: AgentWait(working: now - 9000),
                      ),
                      row(
                        'reply',
                        2,
                        model: 'Fake',
                        wait: AgentWait(
                          stopped: now - 4000,
                          unseen: Unseen(UnseenKind.replied, since: now),
                        ),
                      ),
                      row(
                        'permission',
                        3,
                        model: 'Fake',
                        wait: AgentWait(
                          working: now - 9000,
                          asking: permission(now - 8000),
                        ),
                      ),
                      row(
                        'input',
                        4,
                        model: 'Fake',
                        wait: AgentWait(
                          asking: (
                            on: const InputAsk('Choose it.'),
                            since: now - 8000,
                          ),
                        ),
                      ),
                      row(
                        'gone',
                        5,
                        model: 'Fake',
                        wait: AgentWait(working: now - 9000, exited: true),
                      ),
                      row(
                        'idle',
                        6,
                        model: 'Fake',
                        wait: AgentWait(stopped: now - 4000),
                      ),
                    ],
                    limit: 12,
                    focused: false,
                    palette: palette,
                  ),
                  size: Size(columns, 24),
                ),
              );
              void check(String words, String? colour, bool dim) {
                final y = t.screen.lines.indexWhere(
                  (line) => line.contains(words),
                );
                expect(y, isNot(-1), reason: '$words is visible');
                styled(
                  t.screen,
                  y,
                  words,
                  Style(fg: colour == null ? null : fg(colour), dim: dim),
                );
              }

              check(
                'working 9s',
                theme.endsWith('-ansi') ? palette.success : palette.accent,
                true,
              );
              check('new reply', null, true);
              check('permission 8s', palette.warning, false);
              check('input 8s', palette.warning, false);
              check('exited', palette.error, false);
              check('idle 4s', null, true);
            });
          });
        }
      }
    });
  });

  group('the child line', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      test('names the child in its colour, bold, the rest dim, its age '
          'counting, ${size.width}x${size.height}', () {
        onFakeTime((async, t, draw) {
          draw(
            t.pumpWidget(
              ChildLine(
                name: 'docs',
                runtime: 'fake',
                openedAt: nowMs() - 17000,
                colour: 1,
                model: large,
                palette: dark,
              ),
              size: size,
            ),
          );
          const line = 'docs · fake · $large · opened by main 17s ago';
          expect(t.screen.lines.first, line);
          styled(
            t.screen,
            0,
            'docs',
            Style(fg: fg(dark.agents![1]), bold: true),
          );
          styled(
            t.screen,
            0,
            ' · fake · $large · opened by main 17s ago',
            const Style(dim: true),
          );
          expect(async.periodicTimerCount, 1);
          async.elapse(const Duration(seconds: 1));
          draw(t.pump());
          expect(t.screen.lines.first, contains('opened by main 18s ago'));
        });
      });
    }

    test("a fork's line says what it was forked from", () {
      onFakeTime((async, t, draw) {
        draw(
          t.pumpWidget(
            ChildLine(
              name: 'fork',
              runtime: 'claude',
              openedAt: nowMs() - 120000,
              colour: 0,
              model: 'Opus',
              forkedFrom: 'main',
              palette: plainPalette,
            ),
            size: const Size(80, 24),
          ),
        );
        expect(
          t.screen.lines.first,
          'fork · claude · Opus · forked from main 2m ago',
        );
        expect(t.screen.styleAt(0, 0), const Style(bold: true));
      });
    });
  });

  group('the clock', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      test('ticks while a row is timed: idle 5s is 6s a second on, '
          '${size.width}x${size.height}', () {
        onFakeTime((async, t, draw) {
          draw(
            t.pumpWidget(
              bottom(
                AgentsList(
                  rows: moment(nowMs(), idleMain: 5, idleParser: 7, asking: 8),
                  limit: agentsRowLimit(size.height),
                  focused: false,
                  palette: dark,
                ),
              ),
              size: size,
            ),
          );
          final top = size.height - 3;
          expect(t.screen.lines[top], contains('◦ idle 5s'));
          expect(async.periodicTimerCount, 1);
          async.elapse(const Duration(milliseconds: 999));
          draw(t.pump());
          expect(t.screen.lines[top], contains('◦ idle 5s'));
          async.elapse(const Duration(milliseconds: 1));
          draw(t.pump());
          expect(t.screen.lines[top], contains('◦ idle 6s'));
          expect(t.screen.lines[top + 2], contains('● permission 9s'));
        });
      });
    }

    test('stops when every row is gone, and starts again when one is back', () {
      onFakeTime((async, t, draw) {
        final rows = ValueNotifier<List<AgentRow>>([
          row('main', 1, picked: true, wait: AgentWait(stopped: nowMs())),
          row('parser', 2, colour: 0, wait: AgentWait(working: nowMs())),
        ]);
        draw(
          t.pumpWidget(
            ListenableBuilder(
              listenable: rows,
              builder: (_) => AgentsList(
                rows: rows.value,
                limit: 6,
                focused: false,
                palette: dark,
              ),
            ),
            size: const Size(80, 24),
          ),
        );
        expect(async.periodicTimerCount, 1);
        rows.value = [
          row('main', 1, picked: true, wait: const AgentWait(exited: true)),
          row('parser', 2, colour: 0, failed: true),
        ];
        draw(t.pump());
        expect(t.screen, shows('✗ exited'));
        expect(t.screen, shows('✗ failed to start'));
        expect(async.periodicTimerCount, 0);
        expect(AgentsClock.running, isFalse);
        async.elapse(const Duration(seconds: 5));
        draw(t.pump());
        expect(async.periodicTimerCount, 0);
        rows.value = [
          rows.value.first,
          row('parser', 2, colour: 0, wait: AgentWait(stopped: nowMs())),
        ];
        draw(t.pump());
        expect(async.periodicTimerCount, 1);
        rows.dispose();
      });
    });

    test('two subscribers share one timer, released on the last dispose', () {
      onFakeTime((async, t, draw) {
        final shown = ValueNotifier((list: true, line: true));
        final opened = nowMs();
        draw(
          t.pumpWidget(
            ListenableBuilder(
              listenable: shown,
              builder: (_) => Column(
                children: [
                  if (shown.value.line)
                    ChildLine(
                      name: 'docs',
                      runtime: 'fake',
                      openedAt: opened,
                      colour: 1,
                      palette: dark,
                    ),
                  const Expanded(child: SizedBox()),
                  if (shown.value.list)
                    AgentsList(
                      rows: [
                        row('main', 1, wait: AgentWait(stopped: opened)),
                        row(
                          'docs',
                          3,
                          colour: 1,
                          picked: true,
                          wait: AgentWait(stopped: opened),
                        ),
                      ],
                      limit: 6,
                      focused: false,
                      palette: dark,
                    ),
                ],
              ),
            ),
            size: const Size(80, 24),
          ),
        );
        expect(AgentsClock.subscribers, 2);
        expect(async.periodicTimerCount, 1);
        async.elapse(const Duration(seconds: 1));
        draw(t.pump());
        // The ages move together.
        expect(t.screen, shows('opened by main 1s ago'));
        expect(t.screen, shows('◦ idle 1s'));
        // The first leaves: the timer stays and the other still ticks.
        shown.value = (list: false, line: true);
        draw(t.pump());
        expect(AgentsClock.subscribers, 1);
        expect(async.periodicTimerCount, 1);
        async.elapse(const Duration(seconds: 1));
        draw(t.pump());
        expect(t.screen, shows('opened by main 2s ago'));
        // The last leaves: the timer goes, and nothing ticks after.
        shown.value = (list: false, line: false);
        draw(t.pump());
        expect(AgentsClock.subscribers, 0);
        expect(AgentsClock.running, isFalse);
        expect(async.periodicTimerCount, 0);
        shown.dispose();
      });
    });
  });
}

void testerAgentsWidgetBoundaries() {
  group('tester: agent widget size and subscription boundaries', () {
    for (final size in const [
      Size(0, 0),
      Size(1, 1),
      Size(80, 24),
      Size(120, 40),
    ]) {
      test(
        'Unicode rows survive resize from $size and release the shared clock',
        () {
          onFakeTime((async, t, draw) {
            final start = nowMs();
            draw(
              t.pumpWidget(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChildLine(
                      name: '界🙂e\u0301',
                      runtime: 'fake',
                      openedAt: start - 1000,
                      colour: 0,
                      palette: dark,
                    ),
                    AgentsList(
                      rows: [
                        row(
                          'main',
                          1,
                          model: null,
                          wait: AgentWait(stopped: start - 5000),
                        ),
                        row(
                          '界🙂e\u0301',
                          2,
                          model: null,
                          colour: 0,
                          picked: true,
                        ),
                      ],
                      limit: 6,
                      focused: true,
                      palette: dark,
                    ),
                  ],
                ),
                size: size,
              ),
            );
            expect(AgentsClock.subscribers, 2);
            expect(async.periodicTimerCount, 1);
            async.elapse(const Duration(seconds: 1));
            draw(t.resize(const Size(120, 40)));
            expect(t.screen, shows('界🙂e\u0301'));
            expect(t.screen, shows('opened by main 2s ago'));
            expect(t.screen, shows('idle 6s'));
            draw(t.pumpWidget(const SizedBox()));
            expect(AgentsClock.subscribers, 0);
            expect(async.periodicTimerCount, 0);
            async.elapse(const Duration(seconds: 3));
            draw(t.pump());
            expect(t.screen.text, isEmpty);
          });
        },
      );
    }

    test(
      'an unbounded row constraint still draws only intrinsic list cells',
      () {
        onFakeTime((async, t, draw) {
          draw(
            t.pumpWidget(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AgentsList(
                    rows: [
                      row('main', 1, model: null),
                      row('docs', 2, model: null),
                    ],
                    limit: 4,
                    focused: false,
                    palette: plainPalette,
                  ),
                ],
              ),
              size: const Size(80, 24),
            ),
          );
          expect(t.screen, shows('main'));
          expect(t.screen, shows('docs'));
          expect(AgentsClock.subscribers, 1);
          expect(async.periodicTimerCount, 1);
        });
      },
    );

    test(
      'one thousand updates before a frame keep one subscription and the latest row',
      () {
        onFakeTime((async, t, draw) {
          final start = nowMs();
          final state = ValueNotifier<(List<AgentRow>, bool)>((
            [
              row('main', 1, model: null, wait: AgentWait(stopped: start)),
              row('initial', 2, model: null),
            ],
            false,
          ));
          draw(
            t.pumpWidget(
              ListenableBuilder(
                listenable: state,
                builder: (_) => AgentsList(
                  rows: state.value.$1,
                  limit: 6,
                  focused: state.value.$2,
                  palette: dark,
                ),
              ),
              size: const Size(80, 24),
            ),
          );
          for (var i = 0; i < 1000; i++) {
            state.value = (
              [
                state.value.$1.first,
                row(
                  '界🙂e\u0301 $i',
                  2,
                  model: null,
                  picked: true,
                  failed: i.isEven,
                  wait: AgentWait(working: start),
                ),
              ],
              i.isOdd,
            );
          }
          expect(AgentsClock.subscribers, 1);
          draw(t.pump());
          expect(t.screen, shows('界🙂e\u0301 999'));
          expect(t.screen, shows('❯'));
          expect(async.periodicTimerCount, 1);
          async.elapse(const Duration(seconds: 1));
          draw(t.pump());
          expect(t.screen, shows('working 1s'));
          draw(t.pumpWidget(const SizedBox()));
          state.dispose();
          expect(AgentsClock.subscribers, 0);
          expect(async.periodicTimerCount, 0);
        });
      },
    );
  });
}
