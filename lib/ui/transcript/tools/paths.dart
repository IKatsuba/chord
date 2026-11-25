import 'dart:io';

import 'package:path/path.dart' as p;

/// The session and home directories, as given and resolved through links.
final class PathView {
  /// Bases kept for this session only.
  const PathView(this.cwds, this.homes);

  /// Session directories, given form first.
  final List<String> cwds;

  /// Home directories, given form first.
  final List<String> homes;
}

/// Resolves the display bases once, preserving their given spellings.
PathView pathView(String cwd, String? home, {String Function(String)? real}) {
  final resolve = real ?? _realOrSame;
  return PathView(
    List.unmodifiable({cwd, resolve(cwd)}),
    List.unmodifiable(home == null ? <String>{} : {home, resolve(home)}),
  );
}

String _realOrSame(String path) {
  try {
    return Directory(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return path;
  }
}

String? _under(String base, String path) {
  final rel = p.relative(path, from: base);
  return rel == '..' || rel.startsWith('../') || p.isAbsolute(rel)
      ? null
      : rel == '.'
      ? ''
      : rel;
}

String? _fromHome(String path, PathView view) {
  for (final home in view.homes) {
    final rel = _under(home, path);
    if (rel != null) return rel.isEmpty ? '~' : '~/$rel';
  }
  return null;
}

/// Names a file relative to the session, then home, else whole.
String shownFile(String path, PathView? view) {
  if (view == null || !p.isAbsolute(path)) return path;
  for (final cwd in view.cwds) {
    final rel = _under(cwd, path);
    if (rel != null) return rel.isEmpty ? '.' : rel;
  }
  return _fromHome(path, view) ?? path;
}

/// Names a directory as the header does, preserving session link spelling.
String shownDirectory(String path, PathView? view) {
  if (view == null || !p.isAbsolute(path)) return path;
  var named = path;
  for (final cwd in view.cwds) {
    final rel = _under(cwd, path);
    if (rel != null && view.cwds.isNotEmpty) {
      named = p.join(view.cwds.first, rel);
      break;
    }
  }
  return _fromHome(named, view) ?? named;
}
