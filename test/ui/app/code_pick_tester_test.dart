import 'dart:async';

import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_window_test.dart'
    show selectionConnection, selectionLaunch, primary;

void main() {
  group(
    'tester: real empty-code activation preserves existing copy ownership',
    () {
      for (final size in [const Size(120, 40), const Size(80, 24)]) {
        for (final button in [false, true]) {
          testWidgets(
            'empty ${button ? 'button' : 'keyboard'} preserves pending code and completed note $size',
            (t) async {
              final connection = selectionConnection([
                model.AssistantEntry(
                  'codes',
                  TextRun.empty.plus('```ts\npayload\n```\n\n```json\n```'),
                ),
              ]);
              addTearDown(connection.close);
              final pending = Completer<copy.CopyResult>();
              final attempts = <String>[];
              late bool Function() cancelled;
              await t.pumpWidget(
                TranscriptWindow(
                  launch: selectionLaunch,
                  connection: connection,
                  copyOnSelect: false,
                  copy: (text, token) {
                    attempts.add(text);
                    if (attempts.length == 1) {
                      cancelled = () => token.isCancelled;
                    }
                    return pending.future;
                  },
                ),
                size: size,
              );
              final focus = t.focusManager.primaryFocus;
              Future<void> click(String label) async {
                final row = t.screen.lines.indexWhere(
                  (line) => line.contains('┌─ $label'),
                );
                expect(row, greaterThanOrEqualTo(0));
                final at = Offset(t.screen.lines[row].indexOf('[copy]'), row);
                await t.mouse(primary(MouseEventKind.press, at));
                await t.mouse(primary(MouseEventKind.release, at));
              }

              Future<void> empty() async {
                if (button) {
                  await click('json');
                } else {
                  await t.press('ctrl+x b c');
                }
              }

              if (button) {
                await click('ts');
              } else {
                await t.press('ctrl+x b up c');
              }
              expect(attempts, ['payload']);
              await empty();
              expect(attempts, ['payload']);
              expect(cancelled(), isFalse);
              expect(t.screen, isNot(shows('another block')));
              pending.complete(const copy.CopyResult.sent());
              await t.pump();
              expect(
                t.screen,
                shows("sent 7 chars to the terminal's clipboard"),
              );
              await empty();
              expect(attempts, ['payload']);
              expect(
                t.screen,
                shows("sent 7 chars to the terminal's clipboard"),
              );
              expect(t.screen, isNot(shows('sent 0 chars')));
              expect(t.focusManager.primaryFocus, same(focus));
              expect(connection.app.value.draft, isEmpty);
              expect(t.exitRequested, isFalse);
            },
          );
        }
      }
    },
  );
}
