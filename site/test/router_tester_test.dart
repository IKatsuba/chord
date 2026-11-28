import 'package:chord_site/router.dart';
import 'package:test/test.dart';

const _router = SiteRouter(
  recordings: ['permission'],
  examples: ['markdown', 'text_area'],
);

void main() {
  group('tester: non-root route round trips', () {
    for (final base in [
      '/',
      '/chord/',
      '/chord',
      '/docs/chord/',
      '/chord/chord/',
    ]) {
      test('all routes and their parents remain under $base', () {
        for (final route in const <SiteRoute>[
          HomeRoute(),
          ChordRoute(),
          RecordingRoute('permission'),
          ChordTuiRoute(),
          GalleryRoute(),
          ExampleRoute('markdown'),
          ExampleRoute('text_area'),
          InstallRoute(),
          NotFoundRoute('/missing/界🙂e\u0301'),
        ]) {
          for (final target in [route, route.parent]) {
            final pathname = pathnameOf(target, base);
            final normalizedBase = base.endsWith('/') ? base : '$base/';
            expect(pathname, startsWith(normalizedBase));
            expect(_router.parse(pathUnderBase(pathname, base)), target);
          }
        }
      });
    }

    test('base stripping requires a whole directory prefix', () {
      expect(pathUnderBase('/chorded/install', '/chord/'), '/chorded/install');
      expect(
        pathUnderBase('/docs/chorded/install', '/docs/chord/'),
        '/docs/chorded/install',
      );
      expect(
        pathUnderBase('/chord/chord_tui/markdown', '/chord/'),
        '/chord_tui/markdown',
      );
      expect(pathUnderBase('/chord/CHORD', '/chord/'), '/CHORD');
      expect(
        _router.parse(pathUnderBase('/chord/CHORD', '/chord/')),
        const NotFoundRoute('/CHORD'),
      );
    });

    test('unknown paths keep their exact spelling and separators', () {
      for (final path in [
        '/missing/',
        '/chord_tui//markdown',
        '/chord_tui/markdown//',
        '/chord_tui/%6darkdown',
        '/界🙂e\u0301',
      ]) {
        expect(_router.parse(path), NotFoundRoute(path));
        expect(
          pathUnderBase(pathnameOf(NotFoundRoute(path), '/docs/'), '/docs/'),
          path,
        );
      }
    });
  });
}
