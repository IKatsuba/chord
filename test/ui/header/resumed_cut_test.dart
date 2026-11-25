import 'package:chord/ui/header/compact.dart';
import 'package:chord/ui/header/resumed.dart';
import 'package:chord/ui/transcript/selection.dart';
import 'package:chord/ui/pickers/mcp.dart' show cutPath;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  _testerHeaderCutBoundaries();
  for (final size in const [Size(120, 40), Size(80, 24), Size(32, 10)]) {
    for (final ansi in [false, true]) {
      testWidgets(
        'all nonwrapped header rows share original middle CUT $ansi $size',
        (t) async {
          String words(String value) => ansi ? '\x1b[31m$value\x1b[0m' : value;
          final version = words('test-${'build 界😀 é ' * 24}VERSIONTAIL');
          final agent = words('agent-${'name 界😀 é ' * 24}AGENTTAIL');
          final model = words('model-${'choice 界😀 é ' * 24}MODELTAIL');
          final directory = '/project/${'長😀directory/' * 24}DIRECTORYTAIL';
          final room = (size.width - 7).clamp(0, unbounded);
          final expectedRows = [
            'chord v$version',
            '$agent · $model',
            cutPath(directory, room),
            '? for shortcuts · /help',
          ];
          await t.pumpWidget(
            Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final text in expectedRows)
                    Text(
                      text,
                      softWrap: false,
                      maxLines: 1,
                      overflow: TextOverflow.middle,
                    ),
                ],
              ),
            ),
            size: size,
          );
          final expected = [
            for (final line in t.screen.lines.take(4)) line.substring(7),
          ];
          if (!ansi) {
            expect(expected[0].trimRight(), endsWith('VERSIONTAIL'));
            expect(expected[1].trimRight(), endsWith('MODELTAIL'));
          }
          final source = headerSelectionSource(
            id: 'header',
            revision: 1,
            width: size.width,
            version: version,
            agent: agent,
            model: model,
            directory: directory,
          );
          for (final selectable in [false, true]) {
            await t.pumpWidget(
              CompactHeader(
                version: version,
                agent: agent,
                model: model,
                directory: directory,
                selectionSource: selectable ? source : null,
              ),
              size: size,
            );
            expect(
              [for (final line in t.screen.lines.take(4)) line.substring(7)],
              expected,
              reason: 'selectable=$selectable',
            );
          }
        },
      );
    }

    for (final ansi in [false, true]) {
      testWidgets(
        'resumed fallback uses middle CUT in both header paths $ansi $size',
        (t) async {
          final text = 'resumed · ${'wide 界😀 é label ' * 16}TAIL';
          final facts = ResumedHeader(
            ansi ? '\x1b[31m$text\x1b[0m' : text,
            wrap: false,
          );
          final source = headerSelectionSource(
            id: 'header',
            revision: 1,
            width: size.width,
            version: 'test',
            agent: 'fake',
            directory: 'project',
            resumed: facts,
          );
          final logicalId = selectionChild(source, 'resumed').id;
          await t.pumpWidget(
            Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Text(
                facts.text,
                style: Style.dim,
                softWrap: false,
                maxLines: 1,
                overflow: TextOverflow.middle,
              ),
            ),
            size: size,
          );
          final expected = t.screen.lines.first;
          if (!ansi) {
            expect(expected, contains('resumed'));
            expect(expected.trimRight(), endsWith('TAIL'));
            expect(expected, contains('...'));
          }
          for (final selectable in [false, true]) {
            await t.pumpWidget(
              CompactHeader(
                version: 'test',
                agent: 'fake',
                directory: 'project',
                resumed: facts,
                selectionSource: selectable ? source : null,
              ),
              size: size,
            );
            expect(
              t.screen.lines[4],
              expected,
              reason: 'selectable=$selectable',
            );
            expect(selectionChild(source, 'resumed').id, logicalId);
          }
        },
      );
    }

    testWidgets(
      'titled resumed header keeps wrapped geometry in both paths $size',
      (t) async {
        final facts = ResumedHeader(
          'resumed · ${'titled 界😀 ' * 16}TAIL',
          wrap: true,
        );
        List<String>? drawn;
        for (final selectable in [false, true]) {
          final source = headerSelectionSource(
            id: 'header',
            revision: 1,
            width: size.width,
            version: 'test',
            agent: 'fake',
            directory: 'project',
            resumed: facts,
          );
          await t.pumpWidget(
            CompactHeader(
              version: 'test',
              agent: 'fake',
              directory: 'project',
              resumed: facts,
              selectionSource: selectable ? source : null,
            ),
            size: size,
          );
          if (drawn != null) expect(t.screen.lines, drawn);
          drawn = List.of(t.screen.lines);
          expect(
            t.screen.lines.where((line) => line.contains('titled')).length,
            greaterThan(1),
          );
        }
      },
    );
  }
}

void _testerHeaderCutBoundaries() {
  group('tester: U52d tiny header identity and projection', () {
    testWidgets(
      'tiny resize cycles keep source and direct header cells equal',
      (t) async {
        const resumed = ResumedHeader(
          'resumed · 界🙂é very long fallback TITLETAIL',
          wrap: false,
        );
        Object? identity;
        var revision = 0;
        for (final size in const [
          Size(120, 40),
          Size(80, 24),
          Size(10, 8),
          Size(8, 8),
          Size(7, 8),
          Size(1, 1),
          Size(0, 0),
          Size(80, 24),
        ]) {
          final source = headerSelectionSource(
            id: 'tester-header',
            revision: revision++,
            width: size.width,
            version: 'long 界🙂é version VERSIONTAIL',
            agent: 'long agent AGENTTAIL',
            directory: 'project',
            resumed: resumed,
          );
          final nextIdentity = selectionChild(source, 'resumed').id;
          if (identity != null) expect(nextIdentity, identity);
          identity = nextIdentity;
          await t.pumpWidget(
            CompactHeader(
              version: 'long 界🙂é version VERSIONTAIL',
              agent: 'long agent AGENTTAIL',
              directory: 'project',
              resumed: resumed,
            ),
            size: size,
          );
          final direct = t.screen.text;
          await t.pumpWidget(
            CompactHeader(
              version: 'long 界🙂é version VERSIONTAIL',
              agent: 'long agent AGENTTAIL',
              directory: 'project',
              resumed: resumed,
              selectionSource: source,
            ),
            size: size,
          );
          expect(t.screen.text, direct);
          expect(t.screen.text, isNot(contains('StateError')));
        }
      },
    );
  });
}
