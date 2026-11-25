import 'package:test/test.dart';

import '../../tool/dev.dart' show fakeRuntimesDefine, fixtureDefine;
import '../../tool/screenshots.dart';

void main() {
  group('tester: screenshot selection and fake launch boundaries', () {
    test('overlapping names select each shot once in canonical order', () {
      expect(
        chosen(['logo-light', 'edit', 'logo', 'edit']).map((shot) => shot.name),
        ['edit', 'logo-dark', 'logo-light'],
      );
      expect(chosen(['unknown-shot']), isEmpty);
    });

    test('a fake command does not substitute for the fixture define', () {
      expect(
        () => checkedShotArgv([
          'dart',
          'run',
          fakeRuntimesDefine,
          '/fixture/bin/chord.dart',
          'claude',
          '--agent-command',
          'fake',
        ]),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(fixtureDefine),
          ),
        ),
      );
    });

    test('fake command paths are quoted without changing project argv', () {
      final argv = shotArgv(
        dart: '/fixture/dart',
        portDir: '/fixture/port with spaces',
        args: ['claude'],
        fake: [
          '/fixture/dart',
          '/fixture/fake with spaces.dill',
          '--tokens-only',
        ],
        project: '/fixture/project with spaces',
      );
      expect(argv, contains(fixtureDefine));
      expect(argv, contains(fakeRuntimesDefine));
      expect(
        argv[argv.indexOf('--agent-command') + 1],
        "/fixture/dart '/fixture/fake with spaces.dill' --tokens-only",
      );
      expect(argv.sublist(argv.length - 2), [
        '-C',
        '/fixture/project with spaces',
      ]);
    });
  });
  group('tester: screenshot ANSI state boundaries', () {
    test('empty frames and blank rows remain visible HTML rows', () {
      expect(rowsHtml(styledRows('')), '<div class="row"> </div>');
      expect(
        rowsHtml(styledRows('\n')),
        '<div class="row"> </div>'
        '<div class="row"> </div>',
      );
    });

    test('selective resets clear styles across rows without losing text', () {
      final rows = styledRows(
        '\x1b[1;2;3;4;31;44mstyled\n'
        '\x1b[22;23;24;39;49m<界👩‍💻e\u0301&>',
      );
      final first = rows.first.single;
      expect(
        [first.bold, first.dim, first.italic, first.underline],
        [true, true, true, true],
      );
      final last = rows.last.single;
      expect(
        [last.bold, last.dim, last.italic, last.underline],
        [false, false, false, false],
      );
      expect(last.fg, isNull);
      expect(last.bg, isNull);
      expect(plainOf(rows.last), '<界👩‍💻e\u0301&>');
      expect(
        rowsHtml([rows.last]),
        '<div class="row">&lt;界👩‍💻e\u0301&amp;&gt;</div>',
      );
    });

    test('a thousand style updates before text retain only the last state', () {
      final frame = StringBuffer();
      for (var i = 0; i < 1000; i++) {
        frame.write('\x1b[38;5;${i.isEven ? 244 : 196}m');
      }
      frame.write('界👩‍💻e\u0301');
      final rows = styledRows(frame.toString());
      expect(rows, hasLength(1));
      expect(plainOf(rows.single), '界👩‍💻e\u0301');
      expect(rows.single.single.fg, [255, 0, 0]);
      expect(rowsHtml(rows), isNot(contains('\x1b')));
    });
  });
}
