/// Builds the site into `site/build/`, and serves it:
///
///     dart run tool/build.dart build [--base=/]
///     dart run tool/build.dart serve [--base=/] [--port=8080]
///
/// `build` compiles `web/main.dart` to Wasm with chord's version and the
/// recordings' names, writes `index.html` with `<base href>` from `--base`,
/// and copies in wterm, the font and `docs/images/*.rec.json` as
/// `recordings/`. wterm comes from the npm registry and the font from its
/// own release, each pinned by version and checksum and kept in
/// `.dart_tool/site_cache/`.
///
/// `serve` answers on loopback as a host must ([serve]): files as they are,
/// `index.html` for any other path without an extension, a 404 for a
/// missing file with one, `.wasm` as `application/wasm`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'serving.dart';
import 'sources.dart';

/// A file fetched for the build, pinned by its digest.
class Pinned {
  /// [url], whose [algorithm] digest must be [digest].
  const Pinned({
    required this.name,
    required this.url,
    required this.algorithm,
    required this.digest,
  });

  /// The cache's name for it.
  final String name;

  /// Where it is fetched from.
  final String url;

  /// `sha512` (base64, as npm's integrity) or `sha256` (hex).
  final String algorithm;

  /// The digest it must have.
  final String digest;

  /// Whether [bytes] are this file.
  bool matches(List<int> bytes) => switch (algorithm) {
    'sha512' => base64.encode(sha512.convert(bytes).bytes) == digest,
    'sha256' => sha256.convert(bytes).toString() == digest,
    _ => false,
  };
}

/// wterm's two packages at 0.6.0, as the npm registry's integrity has them.
const wtermDom = Pinned(
  name: 'wterm-dom-0.6.0.tgz',
  url: 'https://registry.npmjs.org/@wterm/dom/-/dom-0.6.0.tgz',
  algorithm: 'sha512',
  digest:
      'c638pHIx3nN0fXP8B/nERAEjBc3GsSbJmW1TN+/WaDLOU97Y/IYw35bargP6e8y8Paq0sF1AnWB9HgKIZR4QBw==',
);

/// wterm's core, which `@wterm/dom` imports.
const wtermCore = Pinned(
  name: 'wterm-core-0.6.0.tgz',
  url: 'https://registry.npmjs.org/@wterm/core/-/core-0.6.0.tgz',
  algorithm: 'sha512',
  digest:
      '5sKuBbMAILn1PyC5AJvTfVo+80nEAoPY+YyN0SYg3KkCV/DyUqdDzFIZQYuJN1ijTWZ/XQLh7hsmZRQtb59IYw==',
);

/// JetBrains Mono 2.304, JetBrains' own release.
const jetBrainsMono = Pinned(
  name: 'JetBrainsMono-2.304.zip',
  url:
      'https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/'
      'JetBrainsMono-2.304.zip',
  algorithm: 'sha256',
  digest: '6f6376c6ed2960ea8a963cd7387ec9d76e3f629125bc33d1fdcd7eb7012f7bbf',
);

/// The font's files the site ships, from the release's zip to the build.
const fontFiles = {
  'fonts/webfonts/JetBrainsMono-Regular.woff2': 'fonts/regular.woff2',
  'fonts/webfonts/JetBrainsMono-Bold.woff2': 'fonts/bold.woff2',
  'OFL.txt': 'fonts/OFL.txt',
};

/// The files of a wterm tarball the page loads: the ES modules, the inlined
/// core Wasm they import and the stylesheet; types and maps stay out.
bool wtermFileShipped(String path) =>
    path == 'package/LICENSE' ||
    path == 'package/src/terminal.css' ||
    (path.startsWith('package/dist/') && path.endsWith('.js'));

/// The bytes of [pinned], from the cache or fetched into it, checked.
Future<List<int>> fetchPinned(Pinned pinned, Directory cache) async {
  final kept = File(p.join(cache.path, pinned.name));
  if (kept.existsSync()) {
    final bytes = kept.readAsBytesSync();
    if (pinned.matches(bytes)) return bytes;
    kept.deleteSync();
  }
  final response = await http.get(Uri.parse(pinned.url));
  if (response.statusCode != 200) {
    throw StateError('${pinned.url}: HTTP ${response.statusCode}');
  }
  final bytes = response.bodyBytes;
  if (!pinned.matches(bytes)) {
    throw StateError('${pinned.url}: its ${pinned.algorithm} is not pinned');
  }
  cache.createSync(recursive: true);
  // Written whole, then moved: a cache never holds half a file.
  final partial = File('${kept.path}.partial')..writeAsBytesSync(bytes);
  partial.renameSync(kept.path);
  return bytes;
}

/// The page with [base] as its `<base href>`.
String pageFor(String template, String base) {
  const placeholder = '<base href="/">';
  if (!template.contains(placeholder)) {
    throw StateError('web/index.html has no $placeholder');
  }
  return template.replaceFirst(
    placeholder,
    '<base href="${const HtmlEscape(HtmlEscapeMode.attribute).convert(base)}">',
  );
}

/// The sizes every shipped shot is recorded at, largest first.
const shotSizes = ['120x36', '80x20', '48x32'];

/// The names of the shots recorded at every one of [shotSizes], from
/// [images]' files.
List<String> recordedShots(Iterable<String> files) {
  final names = <String>{};
  for (final file in files) {
    final match = RegExp(r'^(.+)\.120x36\.rec\.json$').firstMatch(file);
    if (match != null &&
        shotSizes.every(
          (size) => files.contains('${match[1]}.$size.rec.json'),
        )) {
      names.add(match[1]!);
    }
  }
  return names.toList()..sort();
}

/// chord's version, from the root pubspec's `version:` line.
String chordVersionOf(String pubspec) {
  final match = RegExp(
    r'^version:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) throw StateError('pubspec.yaml has no version');
  return match[1]!;
}

Future<void> _build(String base, String siteDir) async {
  final root = p.dirname(siteDir);
  final build = Directory(p.join(siteDir, 'build'));
  final cache = Directory(p.join(siteDir, '.dart_tool', 'site_cache'));
  if (build.existsSync()) build.deleteSync(recursive: true);
  build.createSync(recursive: true);

  final images = Directory(p.join(root, 'docs', 'images'));
  final recordingFiles = [
    for (final file in images.listSync())
      if (file is File && file.path.endsWith('.rec.json'))
        p.basename(file.path),
  ];
  final shots = recordedShots(recordingFiles);
  final version = chordVersionOf(
    File(p.join(root, 'pubspec.yaml')).readAsStringSync(),
  );

  // The code the pages show, from the files themselves.
  writeSources(siteDir);
  stdout.writeln('build: compiling web/main.dart to Wasm');
  final compile = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'wasm',
    '-O4',
    '-DCHORD_VERSION=$version',
    '-DCHORD_RECORDINGS=${shots.join(',')}',
    p.join(siteDir, 'web', 'main.dart'),
    '-o',
    p.join(build.path, 'main.wasm'),
  ]);
  if (compile.exitCode != 0) {
    throw StateError('dart compile wasm:\n${compile.stdout}${compile.stderr}');
  }
  // The source map and the loader's feature probe, which the page does not
  // load, stay out of what a host serves.
  for (final unused in ['main.wasm.map', 'main.support.js']) {
    final file = File(p.join(build.path, unused));
    if (file.existsSync()) file.deleteSync();
  }

  for (final (pinned, folder) in [(wtermDom, 'dom'), (wtermCore, 'core')]) {
    final tar = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(await fetchPinned(pinned, cache)),
    );
    for (final entry in tar.files) {
      if (!entry.isFile || !wtermFileShipped(entry.name)) continue;
      final to = p.join(
        build.path,
        'wterm',
        folder,
        entry.name.substring('package/'.length),
      );
      Directory(p.dirname(to)).createSync(recursive: true);
      File(to).writeAsBytesSync(entry.content);
    }
  }

  final zip = ZipDecoder().decodeBytes(await fetchPinned(jetBrainsMono, cache));
  for (final MapEntry(key: from, value: to) in fontFiles.entries) {
    final entry = zip.findFile(from);
    if (entry == null) {
      throw StateError('$from is not in ${jetBrainsMono.name}');
    }
    final file = File(p.join(build.path, to));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(entry.content);
  }

  final recordings = Directory(p.join(build.path, 'recordings'))..createSync();
  for (final shot in shots) {
    for (final size in shotSizes) {
      File(
        p.join(images.path, '$shot.$size.rec.json'),
      ).copySync(p.join(recordings.path, '$shot.$size.rec.json'));
    }
  }

  File(p.join(build.path, 'index.html')).writeAsStringSync(
    pageFor(
      File(p.join(siteDir, 'web', 'index.html')).readAsStringSync(),
      base,
    ),
  );

  stdout.writeln('build: site/build/, ${shots.length} recordings');
}

Future<void> _serve(String base, int port, String siteDir) async {
  final build = Directory(p.join(siteDir, 'build'));
  if (!build.existsSync()) {
    stderr.writeln('serve: no site/build/; run build first');
    exit(1);
  }
  final files = {
    for (final file in build.listSync(recursive: true))
      if (file is File) p.relative(file.path, from: build.path),
  };
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('serve: http://127.0.0.1:${server.port}$base');
  await for (final request in server) {
    final answer = serve(request.uri.path, base, files);
    switch (answer) {
      case ServedFile(:final file):
        request.response.headers.set('content-type', contentTypeOf(file));
        await request.response.addStream(
          File(p.join(build.path, file)).openRead(),
        );
      case NotServed():
        request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }
}

Future<void> main(List<String> args) async {
  String option(String name, String fallback) {
    for (final arg in args) {
      if (arg.startsWith('--$name=')) return arg.substring(name.length + 3);
    }
    return fallback;
  }

  final siteDir = p.dirname(
    p.dirname(p.absolute(Platform.script.toFilePath())),
  );
  final String base;
  try {
    base = checkedBase(option('base', '/'));
  } on FormatException catch (error) {
    stderr.writeln('build: ${error.message}');
    exit(64);
  }
  switch (args.isEmpty ? '' : args.first) {
    case 'build':
      await _build(base, siteDir);
    case 'serve':
      await _serve(base, int.parse(option('port', '8080')), siteDir);
    default:
      stderr.writeln(
        'usage: dart run tool/build.dart build|serve [--base=/] [--port=8080]',
      );
      exit(64);
  }
}
