import 'package:chord/ui/transcript/tools/paths.dart';
import 'package:test/test.dart';

void main() {
  group('tester U1 path boundaries', () {
    test('normalization cannot shorten a path outside either base', () {
      final view = pathView('/fixture/project', '/fixture', real: (p) => p);
      expect(
        shownFile('/fixture/project/../project-two/a', view),
        '~/project-two/a',
      );
      expect(
        shownFile('/fixture/project/../../elsewhere/a', view),
        '/fixture/project/../../elsewhere/a',
      );
      expect(shownFile('/fixture/project/sub/../a', view), 'a');
      expect(shownDirectory('/fixture/project/sub/..', view), '~/project');
    });

    test('resolved bases are immutable and remain session local', () {
      final calls = <String>[];
      final view = pathView(
        '/fixture/project',
        '/fixture',
        real: (path) {
          calls.add(path);
          return '/resolved$path';
        },
      );
      expect(calls, ['/fixture/project', '/fixture']);
      expect(() => view.cwds.add('/other'), throwsUnsupportedError);
      expect(() => view.homes.clear(), throwsUnsupportedError);
      expect(
        shownFile('/resolved/fixture/project/界👩‍💻e\u0301', view),
        '界👩‍💻e\u0301',
      );
      expect(
        shownDirectory('/resolved/fixture/project/sub', view),
        '~/project/sub',
      );
      expect(calls, hasLength(2));
    });

    test('missing directories retain their given bases without throwing', () {
      final view = pathView('/fixture/missing/project', null);
      expect(view.cwds, ['/fixture/missing/project']);
      expect(view.homes, isEmpty);
      expect(shownFile('/fixture/missing/project/a', view), 'a');
      expect(
        shownFile('/fixture/missing/project-two/a', view),
        '/fixture/missing/project-two/a',
      );
    });
  });
}
