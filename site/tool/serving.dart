/// What a host must answer for the built site, as `build.dart serve` does:
/// the SPA fallback every page's deep link needs.
library;

/// What a request for [path] gets from a site built for [base].
sealed class Served {
  const Served();
}

/// The built file at [file], relative to the build folder.
final class ServedFile extends Served {
  /// The file [file].
  const ServedFile(this.file);

  /// Its path under the build folder.
  final String file;

  @override
  bool operator ==(Object other) => other is ServedFile && other.file == file;

  @override
  int get hashCode => file.hashCode;

  @override
  String toString() => 'ServedFile($file)';
}

/// Nothing: a 404.
final class NotServed extends Served {
  /// A 404.
  const NotServed();

  @override
  bool operator ==(Object other) => other is NotServed;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'NotServed()';
}

/// The answer to [path] for a site built for [base] whose build folder
/// holds [files]: a file that exists is itself; any other path with no
/// file extension is `index.html`, where the app reads the route; a missing
/// path with an extension is a 404, so a broken asset URL fails loudly
/// instead of loading the page as Wasm. Paths outside [base] are 404s.
Served serve(String path, String base, Set<String> files) {
  final root = base.endsWith('/') ? base : '$base/';
  if (path == root.substring(0, root.length - 1)) {
    return const ServedFile('index.html');
  }
  if (!path.startsWith(root)) return const NotServed();
  final rest = Uri.decodeComponent(path.substring(root.length));
  if (rest.split('/').contains('..')) return const NotServed();
  if (rest.isEmpty) return const ServedFile('index.html');
  if (files.contains(rest)) return ServedFile(rest);
  final last = rest.split('/').last;
  return last.contains('.')
      ? const NotServed()
      : const ServedFile('index.html');
}

/// The content type of a built [file]; `.wasm` must be `application/wasm`
/// for the browser to stream-compile it.
String contentTypeOf(String file) => switch (file.split('.').last) {
  'html' => 'text/html; charset=utf-8',
  'js' || 'mjs' => 'text/javascript; charset=utf-8',
  'css' => 'text/css; charset=utf-8',
  'wasm' => 'application/wasm',
  'json' => 'application/json',
  'woff2' => 'font/woff2',
  _ => 'application/octet-stream',
};

/// [base] as the build takes it: it starts and ends with `/`. Throws a
/// [FormatException] for any other.
String checkedBase(String base) {
  if (!base.startsWith('/') || !base.endsWith('/') || base.contains('//')) {
    throw FormatException('--base must start and end with /: $base');
  }
  return base;
}
