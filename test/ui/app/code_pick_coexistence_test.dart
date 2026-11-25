import 'dart:async';
import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'selection_window_test.dart';
import 'code_pick_window_test.dart' show reply, pickHint, pressBounded;

const body =
    'selectable prose\n\n```ts\nfirst code\n```\n\n```dart\nlast code\n```';
Future<void> coexist(WidgetTester t) async {
  await pressBounded(t, 'ctrl+x b');
  expect(t.screen, shows(pickHint));
  await select(t, 'selectable');
  expect(t.screen, shows(pickHint));
  final at = cellOf(t, 'selectable');
  expect(t.screen.styleAt(at.x, at.y).bg, const IndexedColor(66));
}

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final key in ['ctrl+c', 'ctrl+shift+c']) {
      testWidgets(
        'real simultaneous range and pick: $key copies selection and ends picking $size',
        (t) async {
          final connection = selectionConnection([reply(body)]);
          addTearDown(connection.close);
          final writes = <String>[];
          await t.pumpWidget(
            TranscriptWindow(
              launch: selectionLaunch,
              connection: connection,
              copyOnSelect: false,
              copy: (text, _) {
                writes.add(text);
                return const copy.CopyResult.sent();
              },
            ),
            size: size,
          );
          final focus = t.focusManager.primaryFocus;
          await coexist(t);
          await pressBounded(t, key);
          expect(writes, ['selectable']);
          expect(t.screen, isNot(shows(pickHint)));
          expect(t.exitRequested, isFalse);
          expect(t.focusManager.primaryFocus, same(focus));
        },
      );
    }
    testWidgets(
      'real pick arrows/c/Esc clear simultaneous range before pick effects $size',
      (t) async {
        final connection = selectionConnection([reply(body)]);
        addTearDown(connection.close);
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copyOnSelect: false,
            copy: (text, _) {
              writes.add(text);
              return const copy.CopyResult.sent();
            },
          ),
          size: size,
        );
        await coexist(t);
        await pressBounded(t, 'up');
        var at = cellOf(t, 'selectable');
        expect(t.screen.styleAt(at.x, at.y).bg, isNot(const IndexedColor(66)));
        expect(t.screen, shows(pickHint));
        await pressBounded(t, 'c');
        expect(writes, ['first code']);
        await coexist(t);
        await pressBounded(t, 'esc');
        expect(t.screen, isNot(shows(pickHint)));
        at = cellOf(t, 'selectable');
        expect(t.screen.styleAt(at.x, at.y).bg, isNot(const IndexedColor(66)));
        expect(writes, hasLength(1));
        expect(t.exitRequested, isFalse);
      },
    );
    testWidgets(
      'transcript scroll and prefixes preserve both, misses clear without replay $size',
      (t) async {
        final connection = selectionConnection([reply(body)]);
        addTearDown(connection.close);
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copyOnSelect: false,
            copy: (text, _) {
              writes.add(text);
              return const copy.CopyResult.sent();
            },
          ),
          size: size,
        );
        await coexist(t);
        await pressBounded(t, 'pageup pagedown');
        expect(t.screen, shows(pickHint));
        var at = cellOf(t, 'selectable');
        expect(t.screen.styleAt(at.x, at.y).bg, const IndexedColor(66));
        await pressBounded(t, 'ctrl+x');
        expect(t.screen, shows('b a code block'));
        at = cellOf(t, 'selectable');
        expect(t.screen.styleAt(at.x, at.y).bg, const IndexedColor(66));
        await pressBounded(t, 'z');
        expect(t.screen, isNot(shows(pickHint)));
        expect(connection.app.value.draft, isEmpty);
        expect(writes, isEmpty);
        await pressBounded(t, 'ctrl+shift+c');
        expect(writes, isEmpty);
      },
    );
    testWidgets(
      'pending CtrlC fallback, nonrunnable r retains pick and empty paste ends both $size',
      (t) async {
        final connection = selectionConnection([reply(body)]);
        addTearDown(connection.close);
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copyOnSelect: false,
            copy: (text, _) {
              writes.add(text);
              return const copy.CopyResult.sent();
            },
          ),
          size: size,
        );
        await t.type('draft');
        await coexist(t);
        await pressBounded(t, 'ctrl+x ctrl+c');
        expect(connection.app.value.draft, isEmpty);
        expect(writes, isEmpty);
        expect(t.exitRequested, isFalse);
        expect(t.screen, isNot(shows(pickHint)));
        await coexist(t);
        await t.type('r');
        expect(connection.app.value.draft, isEmpty);
        expect(t.screen, shows(pickHint));
        expect(writes, isEmpty);
        await coexist(t);
        await t.paste('');
        expect(connection.app.value.draft, isEmpty);
        expect(t.screen, isNot(shows(pickHint)));
        await pressBounded(t, 'ctrl+shift+c');
        expect(writes, isEmpty);
      },
    );
    testWidgets(
      'same batch pick/move/copy acts once within each key two-pass budget $size',
      (t) async {
        final connection = selectionConnection([reply(body)]);
        addTearDown(connection.close);
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copy: (text, _) {
              writes.add(text);
              return const copy.CopyResult.sent();
            },
          ),
          size: size,
        );
        await pressBounded(t, 'ctrl+x b up c');
        expect(writes, ['first code']);
        expect(connection.app.value.draft, isEmpty);
        expect(t.screen, isNot(shows(pickHint)));
      },
    );
    testWidgets(
      'new picking cancels pending selection copy and old completion cannot end new mode $size',
      (t) async {
        final connection = selectionConnection([reply(body)]);
        addTearDown(connection.close);
        final pending = Completer<copy.CopyResult>();
        late CancellationToken token;
        var calls = 0;
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copyOnSelect: false,
            copy: (text, owned) {
              calls++;
              if (calls == 1) {
                token = owned;
                return pending.future.then((result) {
                  if (!owned.isCancelled) writes.add(text);
                  return result;
                });
              }
              writes.add(text);
              return const copy.CopyResult.sent();
            },
          ),
          size: size,
        );
        await coexist(t);
        await pressBounded(t, 'ctrl+c');
        expect(calls, 1);
        await pressBounded(t, 'ctrl+x b');
        expect(token.isCancelled, isTrue);
        expect(t.screen, shows(pickHint));
        pending.complete(const copy.CopyResult.sent());
        await t.pump();
        expect(writes, isEmpty);
        expect(t.screen, shows(pickHint));
        await pressBounded(t, 'c');
        expect(writes, ['last code']);
      },
    );
    testWidgets(
      'code completion note does not end a newer pick and quit never awaits pending code $size',
      (t) async {
        final connection = selectionConnection([reply(body)]);
        addTearDown(connection.close);
        final pending = <Completer<copy.CopyResult>>[];
        final tokens = <CancellationToken>[];
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copy: (text, token) {
              tokens.add(token);
              final result = Completer<copy.CopyResult>();
              pending.add(result);
              return result.future.then((value) {
                if (!token.isCancelled) writes.add(text);
                return value;
              });
            },
          ),
          size: size,
        );
        await pressBounded(t, 'ctrl+x b c');
        expect(pending, hasLength(1));
        await pressBounded(t, 'ctrl+x b');
        pending.first.complete(const copy.CopyResult.sent());
        await t.pump();
        expect(writes, ['last code']);
        expect(t.screen, shows(pickHint));
        await pressBounded(t, 'c ctrl+d');
        expect(pending, hasLength(2));
        expect(t.exitRequested, isTrue);
        expect(tokens.last.isCancelled, isTrue);
        pending.last.complete(const copy.CopyResult.sent());
        await t.pump();
        expect(writes, ['last code']);
      },
    );
    for (final (tone, theme) in [
      ('dark', ThemeData.dark()),
      ('light', ThemeData.light()),
      ('plain', ThemeData.plain()),
    ]) {
      testWidgets(
        'valid pick survives resize to20 with compact hint and current descriptor $tone $size',
        (t) async {
          final connection = selectionConnection([
            reply(
              'selectable prose\n\n```text\nprior\n```\n\n```ts\ncurrent\n```',
            ),
          ]);
          addTearDown(connection.close);
          final writes = <String>[];
          await t.pumpWidget(
            Theme(
              data: theme,
              child: TranscriptWindow(
                launch: selectionLaunch,
                connection: connection,
                copyOnSelect: false,
                copy: (text, _) {
                  writes.add(text);
                  return const copy.CopyResult.sent();
                },
              ),
            ),
            size: size,
          );
          await pressBounded(t, 'ctrl+x b up c');
          expect(writes, ['prior']);
          expect(t.screen, shows('sent 5 chars'));
          await pressBounded(t, 'ctrl+x b');
          expect(t.screen, shows(pickHint));
          final focus = t.focusManager.primaryFocus;
          await t.resize(const Size(20, 24));
          expect(t.screen, shows('↑ ↓ block'));
          expect(t.screen, isNot(shows('sent 5 chars')));
          expect(t.focusManager.primaryFocus, same(focus));
          expect(connection.app.value.draft, isEmpty);
          expect(writes, ['prior']);
          await pressBounded(t, 'c');
          expect(writes, ['prior', 'current']);
          expect(t.screen, isNot(shows('↑ ↓ block')));
          await pressBounded(t, 'ctrl+x b');
          expect(t.screen, shows('↑ ↓ block'));
          final app = connection.app.value;
          connection.app.value = AppState(
            start: app.start,
            transcript: model.Transcript(
              entries: replacedAt(
                app.transcript.entries,
                0,
                reply('remaining prose without code'),
              ),
            ),
          );
          await pressBounded(t, 'c');
          expect(writes, ['prior', 'current']);
          expect(t.screen, isNot(shows('↑ ↓ block')));
          expect(connection.app.value.draft, isEmpty);
          expect(t.focusManager.primaryFocus, same(focus));
        },
      );
    }
    testWidgets(
      'resize clears range while retaining pick and verbose cancels both $size',
      (t) async {
        final connection = selectionConnection([reply(body)]);
        addTearDown(connection.close);
        final writes = <String>[];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: connection,
            copyOnSelect: false,
            copy: (text, _) {
              writes.add(text);
              return const copy.CopyResult.sent();
            },
          ),
          size: size,
        );
        await coexist(t);
        await t.resize(Size(size.width - 1, size.height));
        expect(t.screen, shows(pickHint));
        final at = cellOf(t, 'selectable');
        expect(t.screen.styleAt(at.x, at.y).bg, isNot(const IndexedColor(66)));
        await pressBounded(t, 'ctrl+shift+c');
        expect(writes, isEmpty);
        await coexist(t);
        await pressBounded(t, 'ctrl+o');
        expect(connection.app.value.expanded, isTrue);
        expect(t.screen, isNot(shows(pickHint)));
        await pressBounded(t, 'ctrl+shift+c');
        expect(writes, isEmpty);
      },
    );
  }
}
