// Original paths_test.ts: all cases carried over; none left out.
import 'package:chord/ui/transcript/tools/paths.dart';
import 'package:test/test.dart';

String linked(String path) =>
    path.replaceFirst(RegExp(r'^/tmp/'), '/private/tmp/');

void main() {
  final view = pathView('/tmp/fixture/src/app', '/tmp/fixture', real: linked);
  test('a view keeps each base as given and as its real path', () {
    expect(view.cwds, ['/tmp/fixture/src/app', '/private/tmp/fixture/src/app']);
    expect(view.homes, ['/tmp/fixture', '/private/tmp/fixture']);
    final plain = pathView('/p', null, real: (path) => path);
    expect(plain.cwds, ['/p']);
    expect(plain.homes, isEmpty);
  });
  test('a file is named from the session directory, by either path', () {
    expect(shownFile('/tmp/fixture/src/app/greet.ts', view), 'greet.ts');
    expect(
      shownFile('/private/tmp/fixture/src/app/src/a.ts', view),
      'src/a.ts',
    );
    expect(shownFile('/private/tmp/fixture/src/app', view), '.');
  });
  test('outside it, from ~; elsewhere, whole', () {
    expect(
      shownFile('/private/tmp/fixture/notes/todo.md', view),
      '~/notes/todo.md',
    );
    expect(shownFile('/etc/hosts', view), '/etc/hosts');
    expect(shownFile('/tmp/fixture/src/app/..hidden', view), '..hidden');
    expect(
      shownFile('/tmp/fixture/src/application/a.ts', view),
      '~/src/application/a.ts',
    );
  });
  test(
    'the session directory through its link reads as the header writes it',
    () {
      final outside = pathView('/tmp/qa', '/tmp/elsewhere', real: linked);
      expect(shownDirectory('/private/tmp/qa', outside), '/tmp/qa');
      expect(shownDirectory('/private/tmp/qa/src', outside), '/tmp/qa/src');
      expect(
        shownDirectory('/private/tmp/other', outside),
        '/private/tmp/other',
      );
    },
  );
  test('a directory is named as the header names one', () {
    expect(shownDirectory('/private/tmp/fixture/src/app', view), '~/src/app');
    expect(shownDirectory('/tmp/fixture', view), '~');
    expect(shownDirectory('/srv/build', view), '/srv/build');
  });
  test(
    'relative spelling is preserved, including parent segments and tilde text',
    () {
      for (final path in [
        '',
        '.',
        '..',
        '../notes.txt',
        './src/../a.ts',
        '~/notes.txt',
        'src/greeting.ts',
        'build',
      ]) {
        expect(shownFile(path, view), path);
        expect(shownDirectory(path, view), path);
      }
    },
  );
  test('with no view, each path is drawn as it came', () {
    expect(shownFile('/a/b.ts', null), '/a/b.ts');
    expect(shownDirectory('/a', null), '/a');
  });
  test('a sibling sharing the home prefix stays absolute', () {
    const path = '/tmp/fixture-other/notes.txt';
    expect(shownFile(path, view), path);
    expect(shownDirectory(path, view), path);
  });
  test('home and session roots have distinct file and directory spellings', () {
    final same = pathView('/tmp/fixture', '/tmp/fixture', real: (path) => path);
    expect(shownFile('/tmp/fixture', same), '.');
    expect(shownDirectory('/tmp/fixture', same), '~');
    expect(shownFile('/tmp/fixture/a.ts', same), 'a.ts');
    expect(shownDirectory('/tmp/fixture/src', same), '~/src');
  });
  test('independent session views do not share their bases', () {
    final first = pathView('/fixture/one', null, real: (path) => path);
    final second = pathView('/fixture/two', null, real: (path) => path);
    expect(shownFile('/fixture/one/a.ts', first), 'a.ts');
    expect(shownFile('/fixture/one/a.ts', second), '/fixture/one/a.ts');
    expect(shownDirectory('/fixture/two', first), '/fixture/two');
    expect(first.cwds, ['/fixture/one']);
    expect(second.cwds, ['/fixture/two']);
  });
  test('spaces and Unicode remain intact after shortening', () {
    expect(
      shownFile('/private/tmp/fixture/src/app/notes/été one.ts', view),
      'notes/été one.ts',
    );
    expect(
      shownDirectory('/private/tmp/fixture/src/app/build output', view),
      '~/src/app/build output',
    );
  });
}
