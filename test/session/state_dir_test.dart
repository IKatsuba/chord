import 'package:chord/session/state_dir.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xdg_directories/xdg_directories.dart' as xdg;

void main() {
  tearDown(() => xdg.xdgEnvironmentOverride = null);
  for (final value in ['state-fixture', '/state-fixture']) {
    test('XDG override $value works without HOME', () {
      xdg.xdgEnvironmentOverride = (key) =>
          key == 'XDG_STATE_HOME' ? value : null;
      expect(chordStateDir(), p.join(value, 'chord'));
    });
  }
  test('empty XDG uses package HOME suffix', () {
    xdg.xdgEnvironmentOverride = (key) =>
        {'HOME': 'fixture-home', 'XDG_STATE_HOME': ''}[key];
    expect(chordStateDir(), p.join('fixture-home', '.local', 'state', 'chord'));
  });
  test('missing or empty HOME and XDG reports the approved requirement', () {
    for (final value in [null, '']) {
      xdg.xdgEnvironmentOverride = (_) => value;
      expect(
        chordStateDir,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'requirement',
            contains('HOME or XDG_STATE_HOME'),
          ),
        ),
      );
    }
  });
}
