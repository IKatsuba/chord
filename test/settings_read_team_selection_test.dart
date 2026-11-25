// A selected run reads the person's teamSelection now, as the original's
// readTeamSelection: the files' merged policy while they read and check,
// a list that only lost bad items included, else a refusal.
import 'dart:io';

import 'package:chord/settings.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late String configHome, cwd;

  setUp(() {
    root = Directory.systemTemp.createTempSync('chord-team-selection-');
    configHome = p.join(root.path, 'config');
    cwd = p.join(root.path, 'work');
    Directory(p.join(configHome, 'chord')).createSync(recursive: true);
    Directory(p.join(cwd, '.chord')).createSync(recursive: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  void user(String text) => File(
    p.join(configHome, 'chord', 'settings.json'),
  ).writeAsStringSync(text);
  void project(String text) =>
      File(p.join(cwd, '.chord', 'settings.json')).writeAsStringSync(text);

  Future<({Map<String, Object?>? policy, String? error})> read() =>
      readTeamSelection(configHome: configHome, cwd: cwd);

  const refused =
      'Team selection settings could not be validated. Correct the settings '
      'before selecting a team.';

  test('no files: an empty policy', () async {
    expect((await read()).policy, isEmpty);
  });

  test(
    "the user's and the project's policies merge, the project's on top",
    () async {
      user(
        '{"teamSelection": {"intent": "economy", "constraints": '
        '{"agents": ["codex"]}}}',
      );
      project('{"teamSelection": {"intent": "fixed"}}');
      final read0 = await read();
      expect(read0.error, isNull);
      expect(read0.policy!['intent'], 'fixed');
      expect((read0.policy!['constraints'] as Map)['agents'], ['codex']);
    },
  );

  test('a file that does not parse, or a teamSelection that does not check, '
      'refuses', () async {
    user('{not json');
    expect((await read()).error, refused);
    user('{"teamSelection": {"intent": "cheapest"}}');
    expect((await read()).error, refused);
  });

  test('another key wrong in the file does not refuse a selection', () async {
    user('{"theme": 5, "teamSelection": {"intent": "economy"}}');
    final read0 = await read();
    expect(read0.error, isNull);
    expect(read0.policy, {'intent': 'economy'});
  });
}
