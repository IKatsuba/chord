// The screenshot tool's pure parts, as the original's
// tests/scripts/dev/screenshots_test.ts checks its own: the shot list, the
// logo crop, the team files beside it, and the frame as HTML; and the
// argv every shot's chord runs with, which only ever starts the fake.
import 'dart:convert';
import 'dart:io';

import 'package:chord/teams.dart';
import 'package:chord/ui/app/start_layout.dart' show tagline;
import 'package:chord_tui/chord_tui.dart' show graphemeWidth;
import 'package:characters/characters.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/dev.dart' show fakeRuntimesDefine, fixtureDefine;
import '../../tool/screenshots.dart';

const _green = '\x1b[38;2;71;231;165m';

int _width(List<Run> row) => plainOf(
  row,
).characters.fold(0, (sum, grapheme) => sum + graphemeWidth(grapheme));

Shot _shot(String name) => shots.singleWhere((shot) => shot.name == name);

void main() {
  test('the shots and logos are the original\'s, in its order', () {
    expect(
      [for (final shot in chosen(const [])) shot.name],
      [
        'start',
        'team',
        'proposal',
        'edit',
        'permission',
        'subagents',
        'agents',
        'resume',
        'codeblocks',
        'fork',
        'logo-dark',
        'logo-light',
      ],
    );
    expect(
      [
        for (final shot in chosen(['logo', 'edit'])) shot.name,
      ],
      ['edit', 'logo-dark', 'logo-light'],
    );
    expect({
      for (final shot in shots) shot.name: shot.scenario,
    }, containsPair('agents', 'agentsquiet'));
    expect(_shot('proposal').team, isFalse);
    expect(logos.map((logo) => logo.theme), ['dark', 'light']);
    expect(logos.every((logo) => logo.first == tagline), isTrue);
  });

  test('start passes no name, waits for the picker, picks nothing, and '
      'leaves out own CLIs', () {
    final start = _shot('start');
    expect(start.args, isEmpty);
    expect(start.first, 'Select agent');
    expect(start.env, contains('PATH=/usr/bin:/bin'));
    expect(start.steps, isEmpty);
  });

  test('every other shot is named, on the prompt', () {
    for (final shot in shots.where((shot) => shot.name != 'start')) {
      expect(shot.args, ['claude'], reason: shot.name);
      expect(shot.first, 'for shortcuts', reason: shot.name);
    }
  });

  test('resume sends three prompts as their own sessions, leaves with '
      '/exit, ages the records, and starts chord --resume', () {
    final steps = _shot('resume').steps;
    final typed = [
      for (final (at, step) in steps.indexed)
        if (step case TypeText(:final text)) (text, steps[at + 1]),
    ];
    expect(
      [for (final (text, _) in typed) text],
      [
        'Explain src/ui/state.ts',
        '/clear',
        'Add a --json flag to the agents command',
        '/clear',
        "Tidy the README's install section",
        '/clear',
        '/exit',
      ],
    );
    for (final (_, next) in typed) {
      expect((next as SendKeys).keys, ['Enter']);
    }
    final tail = steps.sublist(steps.length - 4);
    expect(tail[0], isA<Exited>());
    expect((tail[1] as Aged).hours, [2, 26, 75]);
    expect((tail[2] as Respawn).args, ['--resume']);
    expect((tail[3] as UntilShown).text, 'Resume a session');
  });

  group('the logo crop', () {
    final pad = ' ' * 32;
    final art = [
      for (var at = 0; at < 8; at++)
        '$pad${at.isEven ? '' : ' '}$_green${'▀' * (at + 1)}\x1b[39m    '
            '$_green${'█' * 45}\x1b[39m',
    ];
    final frame = [
      '',
      '',
      ...art,
      '',
      '${' ' * 42}$tagline',
      '${' ' * 48}v0.65.0 · ~/src/app',
      '',
      '    Select agent',
    ].join('\n');

    test("keeps the 8 rows above the tagline's gap, from the art's left "
        'edge, 57 columns and their colours', () {
      final rows = logoRows(frame);
      expect(rows, hasLength(8));
      expect(plainOf(rows[0]), startsWith('▀'));
      expect(plainOf(rows[1]), startsWith(' ▀'));
      for (final row in rows) {
        expect(_width(row), lessThanOrEqualTo(57));
        expect(rowsHtml([row]), contains('color:rgb(71,231,165)'));
        expect(plainOf(row), isNot(contains('v0.65.0')));
      }
    });

    test('a colour opened before the left edge is carried in', () {
      final open = [
        for (final row in art) row.replaceFirst(pad, '$_green$pad'),
        '',
        tagline,
      ].join('\n');
      for (final row in logoRows(open)) {
        expect(row.first.fg, [71, 231, 165]);
      }
    });

    test('wide, combined and joined characters at the right edge keep '
        'their colour and fit', () {
      final content = '${'█' * 50}界é👩‍💻██';
      final rows = logoRows(
        [
          for (var at = 0; at < 8; at++)
            '$_green${' ' * 4}${content}AFTER\x1b[39m',
          '',
          tagline,
        ].join('\n'),
      );
      for (final row in rows) {
        expect(plainOf(row), content);
        expect(_width(row), 57);
        expect(row.every((run) => run.fg != null), isTrue);
      }
    });

    test('the right edge leaves out the next cell; foreground and '
        'background survive the left crop', () {
      final rows = logoRows(
        [
          for (var at = 0; at < 8; at++)
            '$_green\x1b[48;2;21;199;162m${' ' * 32}${'▀' * 57}OUTSIDE\x1b[0m',
          '',
          tagline,
          'v0.65.0',
          'Select agent',
        ].join('\n'),
      );
      for (final row in rows) {
        expect(plainOf(row), '▀' * 57);
        expect(row.single.fg, [71, 231, 165]);
        expect(row.single.bg, [21, 199, 162]);
      }
    });

    test('a frame with no art above its tagline is refused', () {
      expect(
        () => logoRows('Select agent'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no title page art'),
          ),
        ),
      );
      expect(() => logoRows('\n\n$tagline'), throwsStateError);
    });
  });

  group('the frame as HTML', () {
    test("palette colours are the original ansi_up's: the sixteen named, "
        'the cube and the greys', () {
      expect(
        [for (var i = 0; i < 16; i++) paletteRgb(i)],
        [
          [0, 0, 0], [187, 0, 0], [0, 187, 0], [187, 187, 0], //
          [0, 0, 187], [187, 0, 187], [0, 187, 187], [255, 255, 255],
          [85, 85, 85], [255, 85, 85], [0, 255, 0], [255, 255, 85],
          [85, 85, 255], [255, 85, 255], [85, 255, 255], [255, 255, 255],
        ],
      );
      expect(paletteRgb(16), [0, 0, 0]);
      expect(paletteRgb(196), [255, 0, 0]);
      expect(paletteRgb(110), [135, 175, 215]);
      expect(paletteRgb(232), [8, 8, 8]);
      expect(paletteRgb(244), [128, 128, 128]);
      expect(paletteRgb(255), [238, 238, 238]);
      expect(() => paletteRgb(256), throwsRangeError);
      expect(
        rowsHtml(styledRows('\x1b[38;5;244m╭\x1b[31;102mx')),
        '<div class="row"><span style="color:rgb(128,128,128)">╭</span>'
        '<span style="color:rgb(187,0,0);background-color:rgb(0,255,0)">x'
        '</span></div>',
      );
    });

    test("writes ansi_up's inline styles in its order, escaped", () {
      expect(
        rowsHtml(
          styledRows(
            '\x1b[1;2;3;4;38;2;1;2;3;48;5;196m<a & "b">\x1b[0m\x1b[22mx\'',
          ),
        ),
        '<div class="row"><span style="font-weight:bold;opacity:0.7;'
        'font-style:italic;text-decoration:underline;color:rgb(1,2,3);'
        'background-color:rgb(255,0,0)">&lt;a &amp; &quot;b&quot;&gt;</span>'
        'x&#x27;</div>',
      );
    });

    test('a style carries from one row to the next, and an empty row is '
        'one space', () {
      expect(
        rowsHtml(styledRows('\x1b[31ma\n\nb')),
        '<div class="row"><span style="color:rgb(187,0,0)">a</span></div>'
        '<div class="row"> </div>'
        '<div class="row"><span style="color:rgb(187,0,0)">b</span></div>',
      );
    });

    test('a shot is the window of 120 columns on the gradient; a logo is '
        'its art alone', () {
      final shot = page('chord\n');
      expect(shot, contains('width: 120ch'));
      expect(shot, contains('<div class="title">Chorded</div>'));
      expect(
        shot,
        contains('<div class="screen"><div class="row">chord</div></div>'),
      );
      final logo = logoPage(
        [for (var at = 0; at < 8; at++) '█' * 57, '', tagline].join('\n'),
      );
      expect(logo, contains('width: 57ch'));
      expect(logo, isNot(contains('Chorded')));
      expect('<div class="row">'.allMatches(logo), hasLength(8));
    });
  });

  group("every shot's chord", () {
    const fake = ['dart', 'fake.dill', '--tokens-only'];

    test('is built to start only the fake, with its command when it '
        'names an agent', () {
      final named = shotArgv(
        dart: 'dart',
        portDir: '/port',
        args: const ['claude'],
        fake: fake,
        project: '/w/src/app',
      );
      expect(named, [
        'dart',
        'run',
        fixtureDefine,
        fakeRuntimesDefine,
        '/port/bin/chord.dart',
        'claude',
        '--agent-command',
        'dart fake.dill --tokens-only',
        '-C',
        '/w/src/app',
      ]);
      expect(
        shotArgv(
          dart: 'dart',
          portDir: '/port',
          args: const ['--resume'],
          fake: fake,
          project: '/w',
        ),
        containsAllInOrder(['--resume', '--agent-command']),
      );
      expect(
        shotArgv(
          dart: 'dart',
          portDir: '/port',
          args: const [],
          fake: fake,
          project: '/w',
        ).sublist(4),
        ['/port/bin/chord.dart', '-C', '/w'],
      );
    });

    test('is refused without the fake-runtimes define, or starting an '
        'agent without the fake', () {
      expect(
        () => checkedShotArgv([
          'dart',
          'run',
          fixtureDefine,
          '/port/bin/chord.dart',
          'claude',
          '--agent-command',
          'fake',
        ]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(fakeRuntimesDefine),
          ),
        ),
      );
      expect(
        () => checkedShotArgv([
          'dart',
          'run',
          fixtureDefine,
          fakeRuntimesDefine,
          '/port/bin/chord.dart',
          'claude',
          '-C',
          '/w',
        ]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('--agent-command'),
          ),
        ),
      );
    });

    test('runs in its own home and state, under a neutral place, on the '
        "fake's scenario", () {
      final env = shotEnv(_shot('edit'), shotDir('edit'), '/tmp/h');
      expect(shotDir('edit'), '/tmp/chord-shot.edit');
      expect(env, containsAll(['HOME=/tmp/h', 'CHORD_FAKE_SCENARIO=edit']));
      expect(env, contains('XDG_STATE_HOME=/tmp/chord-shot.edit/state'));
      expect(env, contains('XDG_CONFIG_HOME=/tmp/h/.config'));
      expect(shotSettings('light'), containsPair('theme', 'light'));
    });
  });

  test('aging moves each prompted session back by its hours, the latest '
      'first, and leaves the rest', () {
    final dir = Directory.systemTemp.createTempSync('screenshots_age');
    addTearDown(() => dir.deleteSync(recursive: true));
    void write(String name, List<Map<String, Object?>> lines) => File(
      p.join(dir.path, name),
    ).writeAsStringSync('${lines.map(jsonEncode).join('\n')}\n');
    const hour = 3600000;
    write('old.jsonl', [
      {'type': 'start', 'at': 10 * hour},
      {'type': 'prompt', 'at': 11 * hour},
    ]);
    write('new.jsonl', [
      {'type': 'prompt', 'at': 20 * hour},
      {'type': 'note'},
    ]);
    write('none.jsonl', [
      {'type': 'start', 'at': 30 * hour},
    ]);
    age(dir.path, [2, 26]);
    List<Object?> ats(String name) => [
      for (final line in File(p.join(dir.path, name)).readAsLinesSync())
        (jsonDecode(line) as Map)['at'],
    ];
    expect(ats('new.jsonl'), [18 * hour, null]);
    expect(ats('old.jsonl'), [-16 * hour, -15 * hour]);
    expect(ats('none.jsonl'), [30 * hour]);
  });

  group('the team files beside the tool', () {
    for (final file in ['screenshots_team.md', 'screenshots_proposal.md']) {
      test("$file parses with the shots' runtimes, models and modes", () {
        final read = parseTeam(
          'bugfix',
          File(p.join('tool', file)).readAsStringSync(),
          const ['claude', 'codex'],
        );
        final team = read.team!;
        expect(team.lead.agent, 'claude');
        expect(team.lead.model, 'claude-opus-5-5');
        expect(team.lead.mode, 'default');
        expect(
          [for (final m in team.members) (m.name, m.agent, m.model, m.mode)],
          [
            ('tester', 'claude', 'claude-opus-5-5', 'acceptEdits'),
            ('coder', 'codex', 'gpt-6.1-sol', 'auto'),
            ('reviewer', 'claude', 'claude-opus-5-5', 'plan'),
          ],
        );
      });
    }
  });
}
