import 'dart:async';
import 'dart:js_interop';

import 'package:chord_tui/chord_tui.dart';

import '../host.dart';
import '../router.dart';

@JS('location.pathname')
external String get _pathname;

@JS('document.baseURI')
external String get _baseUri;

@JS('history.pushState')
external void _pushState(JSAny? state, String unused, String url);

@JS('window.addEventListener')
external void _addEventListener(String type, JSFunction listener);

/// The site's host in the browser: the address under `<base href>`, the
/// History API, and links through the page's terminal.
class BrowserHost extends SiteHost {
  /// The page's host, opening links through [terminal].
  BrowserHost(this.terminal) {
    _addEventListener(
      'popstate',
      ((JSAny? _) => _pops.add(pathUnderBase(_pathname, _basePath))).toJS,
    );
  }

  /// The terminal the site draws in.
  final Terminal terminal;

  final _pops = StreamController<String>.broadcast();

  String get _basePath => Uri.parse(_baseUri).path;

  @override
  String get initialPath => pathUnderBase(_pathname, _basePath);

  @override
  Stream<String> get pops => _pops.stream;

  @override
  void push(SiteRoute route) {
    _pushState(null, '', pathnameOf(route, _basePath));
    show(route);
  }

  @override
  void show(SiteRoute route) => terminal.setTitle(route.title);

  @override
  void openUrl(String url) => unawaited(terminal.openUrl(url));
}
