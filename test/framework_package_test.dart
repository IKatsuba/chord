import 'dart:io';
import 'dart:isolate';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('tester: renamed framework path dependency', () {
    test('both public entrypoints resolve to the local framework', () async {
      final manifest = loadYaml(File('pubspec.yaml').readAsStringSync());
      final path = manifest['dependencies']['chord_tui']['path'] as String;
      final framework = Directory.fromUri(Directory.current.uri.resolve(path));
      for (final entrypoint in ['chord_tui.dart', 'testing.dart']) {
        final resolved = await Isolate.resolvePackageUri(
          Uri.parse('package:chord_tui/$entrypoint'),
        );
        expect(resolved, isNotNull);
        expect(
          File.fromUri(resolved!).resolveSymbolicLinksSync(),
          File.fromUri(
            framework.uri.resolve('lib/$entrypoint'),
          ).resolveSymbolicLinksSync(),
        );
      }
    });

    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets('public testing import drives framework widgets at $size', (
        tester,
      ) async {
        await tester.pumpWidget(Text('Framework dependency'), size: size);
        expect(tester.screen, shows('Framework dependency'));
      });
    }
  });
}
