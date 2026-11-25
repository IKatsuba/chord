import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/context.dart';
import 'package:chord/ui/header/compact.dart';
import 'package:chord/ui/status/working.dart';
import 'package:chord/ui/transcript/selection.dart';
import 'package:chord/ui/transcript/tools/tool.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../shortcuts/keys_bound_test.dart' show read;

void main() {
  group('tester: bound hints and semantic source parity', () {
    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets('header source matches rebound and absent help hints $size', (
        t,
      ) async {
        for (final key in ['ctrl+t', null]) {
          await t.pumpWidget(
            CompactHeader(
              version: 'test',
              agent: 'fake',
              directory: '.',
              helpKey: key,
            ),
            size: size,
          );
          final plain = t.screen.text;
          final source = headerSelectionSource(
            id: 'header',
            revision: key ?? 'unbound',
            width: size.width,
            version: 'test',
            agent: 'fake',
            directory: '.',
            helpKey: key,
          );
          await t.pumpWidget(
            CompactHeader(
              version: 'test',
              agent: 'fake',
              directory: '.',
              helpKey: key,
              selectionSource: source,
            ),
            size: size,
          );
          expect(t.screen.text, plain);
          expect(
            t.screen.text,
            contains(key == null ? '/help' : '$key for shortcuts'),
          );
          if (key == null) {
            expect(t.screen.text, isNot(contains('for shortcuts')));
          }
        }
      });

      testWidgets(
        'fold source revises its hint when key changes or unbinds $size',
        (t) async {
          final call = model.ToolCall(
            'call',
            title: 'Read file',
            kind: 'read',
            status: 'completed',
            content: [
              acp.ToolCallContent.fromJson({
                'type': 'content',
                'content': {'type': 'text', 'text': '1\n2\n3\n4\n5\n'},
              }),
            ],
          );
          final cache = TranscriptSources('session');
          final entry = model.ToolEntry('turn', call);
          SelectionSource? previous;
          for (final key in ['ctrl+t', null]) {
            final map = read([
              {
                'context': 'Global',
                'bindings': {'ctrl+o': null, ?key: 'app:toggleTranscript'},
              },
            ]);
            await t.pumpWidget(
              Keys(keymap: map, child: Tool(call, expanded: false)),
              size: size,
            );
            final plain = t.screen.text;
            final source = cache.source(
              entry,
              width: size.width,
              expandKey: key,
            );
            if (previous != null) {
              expect(source, isNot(same(previous)));
              expect(source.id, previous.id);
            }
            previous = source;
            await t.pumpWidget(
              Keys(
                keymap: map,
                child: Tool(call, expanded: false, selectionSource: source),
              ),
              size: size,
            );
            expect(t.screen.text, plain);
            expect(
              t.screen.text,
              contains(
                key == null ? '… +2 lines' : '… +2 lines ($key to expand)',
              ),
            );
            if (key == null) {
              expect(t.screen.text, isNot(contains('to expand')));
            }
          }
        },
      );

      testWidgets(
        'working hint updates through Keys and removal stops timers $size',
        (t) async {
          final map = ValueNotifier(
            read([
              {
                'context': 'Chat',
                'bindings': {'escape': null, 'ctrl+t': 'chat:cancel'},
              },
            ]),
          );
          addTearDown(map.dispose);
          await t.pumpWidget(
            ListenableBuilder(
              listenable: map,
              builder: (_) => Keys(
                keymap: map.value,
                child: const Working(turn: model.Working('turn', 0)),
              ),
            ),
            size: size,
          );
          expect(t.screen.text, contains('ctrl+t to interrupt'));
          map.value = read([
            {
              'context': 'Chat',
              'bindings': {'escape': null},
            },
          ]);
          await t.pump();
          expect(t.screen.text, isNot(contains('to interrupt')));
          await t.pumpWidget(Text('removed'), size: size);
          await t.pump(const Duration(milliseconds: 300));
          expect(t.screen.text, startsWith('removed'));
        },
      );
    }
  });
}
