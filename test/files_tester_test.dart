import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/files.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('tester: discovery cancellation and literal link ownership', () {
    test(
      'cancelling an accepted walk does not cancel a fresh walk or links',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'chord-files-tester-',
        );
        addTearDown(() => dir.delete(recursive: true));
        await File(p.join(dir.path, 'visible')).writeAsString('');
        final token = CancellationToken();
        final pending = listFiles(dir.path, cancellationToken: token);
        token.cancel();
        await expectLater(pending, throwsA(isA<CancelledException>()));
        final fresh = await listFiles(dir.path);
        expect(fresh, ['visible']);
        final linkToken = CancellationToken();
        final cancelled = mentionLinks(
          ['visible'],
          dir.path,
          cancellationToken: linkToken,
        );
        linkToken.cancel();
        expect(await cancelled, isEmpty);
        expect(
          (await mentionLinks(['visible'], dir.path)).single.toJson()['name'],
          'visible',
        );
      },
    );

    test(
      'literal Unicode and URI punctuation links preserve alias paths and typed order',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'chord-links-tester-',
        );
        final outside = await Directory.systemTemp.createTemp(
          'chord-link-target-',
        );
        addTearDown(() => dir.delete(recursive: true));
        addTearDown(() => outside.delete(recursive: true));
        final names = ['界 é%?#.txt', 'line\nname.txt'];
        for (final name in names) {
          await File(p.join(dir.path, name)).writeAsString('');
        }
        final target = File(p.join(outside.path, 'target'));
        await target.writeAsString('');
        await Link(p.join(dir.path, 'alias')).create(target.path);
        final input = [
          'alias',
          names[1],
          names[0],
          'alias',
          target.path,
          '../target',
        ];
        final links = await mentionLinks(input, dir.path);
        expect(links.map((link) => link.toJson()['name']), [
          'alias',
          names[1],
          names[0],
        ]);
        for (final link in links) {
          final json = link.toJson();
          expect(
            Uri.parse(json['uri'] as String).toFilePath(),
            p.join(dir.path, json['name'] as String),
          );
        }
        expect(links.first.toJson()['uri'], endsWith('/alias'));
        expect(links[1].toJson()['uri'], contains('%0A'));
        expect(links.last.toJson()['uri'], contains('%25%3F%23'));
        expect(() => links.clear(), throwsUnsupportedError);
        await Link(p.join(dir.path, 'alias')).delete();
        expect(await mentionLinks(['alias'], dir.path), isEmpty);
      },
    );
  });
}
