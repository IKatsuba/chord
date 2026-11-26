import 'router.dart';

/// What the site needs from the page it runs on: its address, the browser's
/// history and its links. The browser gives one in `web/`; tests a fake.
abstract class SiteHost {
  /// For implementations.
  const SiteHost();

  /// The path the visitor opened, under the site's base.
  String get initialPath;

  /// The path under the base each time Back or Forward moves the visitor.
  Stream<String> get pops;

  /// Opens [route] as a new history entry, and names the tab after it.
  void push(SiteRoute route);

  /// Names the tab after [route] without a new history entry.
  void show(SiteRoute route);

  /// Opens [url] in a new tab.
  void openUrl(String url);

  /// The recording file [file] (`<name>.<cols>x<rows>.rec.json`), or null
  /// where it cannot be had.
  Future<String?> recording(String file);
}
