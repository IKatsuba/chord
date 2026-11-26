/// A page of the site, as its path names it.
sealed class SiteRoute {
  const SiteRoute();

  /// The path under the base, `/` for home, without a trailing slash.
  String get path;

  /// The browser tab's title.
  String get title;

  /// Where Esc goes, by the Routes table and not by cutting the path; home
  /// is its own parent, so Esc there does nothing.
  SiteRoute get parent;

  @override
  bool operator ==(Object other) =>
      other is SiteRoute &&
      other.runtimeType == runtimeType &&
      other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => '$runtimeType($path)';
}

/// The home menu.
final class HomeRoute extends SiteRoute {
  /// Home.
  const HomeRoute();

  @override
  String get path => '/';

  @override
  String get title => 'chord and chord_tui';

  @override
  SiteRoute get parent => this;
}

/// chord: what it is, and its screens.
final class ChordRoute extends SiteRoute {
  /// The chord page.
  const ChordRoute();

  @override
  String get path => '/chord';

  @override
  String get title => 'chord';

  @override
  SiteRoute get parent => const HomeRoute();
}

/// One of chord's screens, played from its recording.
final class RecordingRoute extends SiteRoute {
  /// The recording called [name].
  const RecordingRoute(this.name);

  /// The recording's name, as `docs/images/<name>.rec.json` has it.
  final String name;

  @override
  String get path => '/chord/$name';

  @override
  String get title => '$name · chord';

  @override
  SiteRoute get parent => const ChordRoute();
}

/// chord_tui: what it is, and README's example.
final class ChordTuiRoute extends SiteRoute {
  /// The chord_tui page.
  const ChordTuiRoute();

  @override
  String get path => '/chord_tui';

  @override
  String get title => 'chord_tui';

  @override
  SiteRoute get parent => const HomeRoute();
}

/// The list of the framework's examples.
final class GalleryRoute extends SiteRoute {
  /// The gallery.
  const GalleryRoute();

  @override
  String get path => '/chord_tui/gallery';

  @override
  String get title => 'gallery · chord_tui';

  @override
  SiteRoute get parent => const ChordTuiRoute();
}

/// One of the framework's examples, running.
final class ExampleRoute extends SiteRoute {
  /// The example called [name].
  const ExampleRoute(this.name);

  /// The example's name, as its file in `example/` has it.
  final String name;

  @override
  String get path => '/chord_tui/$name';

  @override
  String get title => '$name · chord_tui';

  @override
  SiteRoute get parent => const GalleryRoute();
}

/// How to install chord.
final class InstallRoute extends SiteRoute {
  /// The install page.
  const InstallRoute();

  @override
  String get path => '/install';

  @override
  String get title => 'install · chord';

  @override
  SiteRoute get parent => const HomeRoute();
}

/// A path no page has; it stays visible, with a way home.
final class NotFoundRoute extends SiteRoute {
  /// Nothing at [path].
  const NotFoundRoute(this.path);

  @override
  final String path;

  @override
  String get title => 'not found · chord';

  @override
  SiteRoute get parent => const HomeRoute();
}

/// The site's routes: which recordings and examples have pages.
class SiteRouter {
  /// Pages for [recordings] and [examples] by name; no example may be
  /// called [galleryName], the gallery's own segment.
  const SiteRouter({required this.recordings, required this.examples});

  /// The segment under `/chord_tui` the gallery has.
  static const galleryName = 'gallery';

  /// The recordings that have pages under `/chord`.
  final List<String> recordings;

  /// The examples that have pages under `/chord_tui`.
  final List<String> examples;

  /// The route of [path], read under the site's base. A trailing slash is
  /// ignored; any other path, a different case included, is not found.
  SiteRoute parse(String path) {
    final trimmed =
        path.length > 1 && path.endsWith('/') && !path.endsWith('//')
        ? path.substring(0, path.length - 1)
        : path;
    final segments = trimmed.split('/');
    if (segments.first.isNotEmpty) return NotFoundRoute(path);
    return switch (segments.skip(1).toList()) {
      [''] => const HomeRoute(),
      ['chord'] => const ChordRoute(),
      ['chord', final name] when recordings.contains(name) => RecordingRoute(
        name,
      ),
      ['chord_tui'] => const ChordTuiRoute(),
      ['chord_tui', galleryName] => const GalleryRoute(),
      ['chord_tui', final name] when examples.contains(name) => ExampleRoute(
        name,
      ),
      ['install'] => const InstallRoute(),
      _ => NotFoundRoute(path),
    };
  }
}

/// The path of [pathname] under [basePath], the path of the page's base
/// URL: `/chord/chord_tui/markdown` under `/chord/` is `/chord_tui/markdown`.
/// A pathname outside the base is given back as it is.
String pathUnderBase(String pathname, String basePath) {
  final base = basePath.endsWith('/') ? basePath : '$basePath/';
  if (pathname == base.substring(0, base.length - 1)) return '/';
  if (!pathname.startsWith(base)) return pathname;
  return '/${pathname.substring(base.length)}';
}

/// The full pathname of [route] under [basePath], for `history.pushState`.
String pathnameOf(SiteRoute route, String basePath) {
  final base = basePath.endsWith('/') ? basePath : '$basePath/';
  return route is HomeRoute ? base : '$base${route.path.substring(1)}';
}
