import 'dart:async';

import 'package:chord_site/host.dart';
import 'package:chord_site/router.dart';

/// A page for the site's tests: an address, a history and links, all kept
/// in memory.
class FakeHost extends SiteHost {
  FakeHost([this.initialPath = '/']);

  @override
  final String initialPath;

  final popped = StreamController<String>.broadcast();
  final pushed = <String>[];
  final titles = <String>[];
  final opened = <String>[];

  @override
  Stream<String> get pops => popped.stream;

  @override
  void push(SiteRoute route) {
    pushed.add(route.path);
    show(route);
  }

  @override
  void show(SiteRoute route) => titles.add(route.title);

  @override
  void openUrl(String url) => opened.add(url);
}
