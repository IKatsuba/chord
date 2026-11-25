/// The NOTICES every archive and npm package carries: the Dart SDK's
/// licence, the licence of every pub package compiled into chord, and the
/// notices the repository retains for code it ported (README.md's credits).
/// The original's `NATIVE_NOTICES` has no counterpart: a Dart binary embeds
/// no native library.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'runner.dart';

/// One notice: what it is for, and its text.
typedef Notice = ({String title, String text});

/// The port's package, from the repository's root: the root itself.
const portFolder = '.';

/// The READMEs whose Credits sections name the files that retain a notice,
/// from the root: the app's, and the framework's, which the published
/// package carries. Each one's links are read from its own folder.
const creditedReadmes = ['README.md', 'packages/chord_tui/README.md'];

/// The packages that are this repository's own code, under its LICENSE.
const ownPackages = {'chord', 'chord_tui'};

const _licenceFiles = [
  'LICENSE',
  'LICENSE.md',
  'LICENSE.txt',
  'LICENCE',
  'COPYING',
];

/// NOTICES' text: [sdk]'s licence first, then [packages], then [retained].
String renderNotices({
  required String sdk,
  required List<Notice> packages,
  required List<Notice> retained,
}) {
  final sections = [
    (title: 'The Dart SDK', text: sdk),
    ...packages,
    ...retained,
  ];
  final body = [
    'chord is built with the Dart SDK and the packages below, and retains '
        'the notices of code it ported. Their licences follow.',
    for (final section in sections)
      '${'-' * 78}\n${section.title}\n\n${section.text.trimRight()}',
  ].join('\n\n');
  return '$body\n';
}

/// The names of the packages compiled into chord, sorted: every package
/// [graph] (`.dart_tool/package_graph.json`) reaches from chord through
/// dependencies, dev dependencies left out, the repository's own left out.
List<String> compiledPackages(Map<String, Object?> graph) {
  final byName = {
    for (final package in graph['packages']! as List<Object?>)
      (package! as Map<String, Object?>)['name']! as String:
          package as Map<String, Object?>,
  };
  final reached = <String>{};
  void reach(String name) {
    if (!reached.add(name)) return;
    final package = byName[name] ?? die('$name is not in the package graph');
    for (final dependency in package['dependencies']! as List<Object?>) {
      reach(dependency! as String);
    }
  }

  reach('chord');
  return reached.difference(ownPackages).toList()..sort();
}

final _creditLink = RegExp(r'\]\(([^)\s]+\.dart)\)');

/// The source files a README's Credits section says retain a notice, as
/// its links give them; [name] is which README, for the refusal.
List<String> creditedFiles(String readme, {String name = 'README.md'}) {
  final section = readme
      .split(RegExp(r'^## ', multiLine: true))
      .firstWhere(
        (part) => part.startsWith('Credits\n'),
        orElse: () => die('$name has no Credits section'),
      );
  return [for (final match in _creditLink.allMatches(section)) match[1]!];
}

/// The leading `//` comment of a source file's [text], the notice it
/// retains, without the comment marks.
String leadingComment(String text) => [
  for (final line in const LineSplitter().convert(text))
    if (line.startsWith('//'))
      line.replaceFirst(RegExp(r'^// ?'), '')
    else
      null,
].takeWhile((line) => line != null).join('\n').trim();

/// NOTICES for the tree at [root], compiled with the SDK at [sdkDir].
/// Dies when a licence or notice is missing or empty, as a release may not
/// ship without it.
String collectNotices({required String root, required String sdkDir}) {
  String read(String path, String what) {
    final file = File(path);
    if (!file.existsSync()) die('$what is missing: $path');
    return file.readAsStringSync();
  }

  final tool = p.normalize(p.join(root, portFolder, '.dart_tool'));
  final graph =
      jsonDecode(read(p.join(tool, 'package_graph.json'), 'The package graph'))
          as Map<String, Object?>;
  final configPath = p.join(tool, 'package_config.json');
  final config =
      jsonDecode(read(configPath, 'The package config'))
          as Map<String, Object?>;
  // A relative rootUri is relative to the config file itself.
  final base = p.toUri(configPath);
  final roots = {
    for (final entry in config['packages']! as List<Object?>)
      (entry! as Map<String, Object?>)['name']! as String: p.fromUri(
        base.resolve('${(entry as Map<String, Object?>)['rootUri']}/'),
      ),
  };
  final versions = {
    for (final entry in graph['packages']! as List<Object?>)
      (entry! as Map<String, Object?>)['name']! as String:
          (entry as Map<String, Object?>)['version'] as String?,
  };

  final packages = [
    for (final name in compiledPackages(graph))
      (
        title: [name, ?versions[name]].join(' '),
        text: _required(
          _licenceOf(name, roots[name] ?? die('$name has no root')),
          "$name's licence",
        ),
      ),
  ];
  final credited = [
    for (final readme in creditedReadmes)
      for (final file in creditedFiles(
        read(p.join(root, readme), 'README'),
        name: readme,
      ))
        p.normalize(p.join(p.dirname(readme), file)),
  ];
  final retained = [
    for (final file in credited)
      (
        title: 'Retained in $file',
        text: _required(
          leadingComment(read(p.join(root, file), 'A credited file')),
          'The notice retained in $file',
        ),
      ),
  ];
  return renderNotices(
    sdk: _required(
      read(p.join(sdkDir, 'LICENSE'), "The Dart SDK's licence"),
      "The Dart SDK's licence",
    ),
    packages: packages,
    retained: retained,
  );
}

String _licenceOf(String name, String root) {
  for (final candidate in _licenceFiles) {
    final file = File(p.join(root, candidate));
    if (file.existsSync()) return file.readAsStringSync();
  }
  die('$name has no licence file in $root');
}

// A licence or notice that is there but empty is as missing: NOTICES may
// not ship without it.
String _required(String text, String what) =>
    text.trim().isEmpty ? die('$what is empty') : text;
