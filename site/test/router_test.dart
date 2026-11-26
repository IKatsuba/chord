import 'package:chord_site/router.dart';
import 'package:test/test.dart';

const _router = SiteRouter(
  recordings: ['permission', 'start'],
  examples: ['markdown', 'picker'],
);

void main() {
  test('every page has its path, and the path its page', () {
    for (final route in const <SiteRoute>[
      HomeRoute(),
      ChordRoute(),
      RecordingRoute('permission'),
      ChordTuiRoute(),
      GalleryRoute(),
      ExampleRoute('markdown'),
      InstallRoute(),
    ]) {
      expect(_router.parse(route.path), route, reason: route.path);
    }
  });

  test('a trailing slash is ignored', () {
    expect(
      _router.parse('/chord_tui/markdown/'),
      const ExampleRoute('markdown'),
    );
    expect(_router.parse('/install/'), const InstallRoute());
  });

  test('unknown segments, another case and deeper paths are not found', () {
    for (final path in [
      '/chord_tui/markdwon',
      '/Chord',
      '/chord/nothing',
      '/chord_tui/markdown/more',
      '/x',
      'chord',
      '//',
    ]) {
      expect(_router.parse(path), NotFoundRoute(path), reason: path);
    }
  });

  test('esc goes where the Routes table says', () {
    expect(const ExampleRoute('markdown').parent, const GalleryRoute());
    expect(const GalleryRoute().parent, const ChordTuiRoute());
    expect(const ChordTuiRoute().parent, const HomeRoute());
    expect(const RecordingRoute('start').parent, const ChordRoute());
    expect(const ChordRoute().parent, const HomeRoute());
    expect(const InstallRoute().parent, const HomeRoute());
    expect(const NotFoundRoute('/x').parent, const HomeRoute());
    expect(const HomeRoute().parent, const HomeRoute());
  });

  test('titles name the page and its part of the site', () {
    expect(const HomeRoute().title, 'chord and chord_tui');
    expect(const ChordRoute().title, 'chord');
    expect(const RecordingRoute('permission').title, 'permission · chord');
    expect(const ChordTuiRoute().title, 'chord_tui');
    expect(const GalleryRoute().title, 'gallery · chord_tui');
    expect(const ExampleRoute('markdown').title, 'markdown · chord_tui');
    expect(const InstallRoute().title, 'install · chord');
    expect(const NotFoundRoute('/x').title, 'not found · chord');
  });

  test("no example of the site's is named as the gallery", () {
    expect(siteRouter.examples, isNot(contains(SiteRouter.galleryName)));
    expect(
      siteRouter.parse('/chord_tui/${SiteRouter.galleryName}'),
      const GalleryRoute(),
    );
  });

  test('paths are read under the base and written back under it', () {
    expect(
      pathUnderBase('/chord/chord_tui/markdown', '/chord/'),
      '/chord_tui/markdown',
    );
    expect(pathUnderBase('/chord/', '/chord/'), '/');
    expect(pathUnderBase('/chord', '/chord/'), '/');
    expect(pathUnderBase('/install', '/'), '/install');
    expect(pathUnderBase('/elsewhere', '/chord/'), '/elsewhere');
    expect(
      pathnameOf(const ExampleRoute('markdown'), '/chord/'),
      '/chord/chord_tui/markdown',
    );
    expect(pathnameOf(const HomeRoute(), '/chord/'), '/chord/');
    expect(pathnameOf(const InstallRoute(), '/'), '/install');
  });
}
