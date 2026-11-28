import 'dart:async';
import 'dart:convert';

import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'fake_host.dart';

String recording(int cols, int rows) => jsonEncode({
  'version': 1,
  'cols': cols,
  'rows': rows,
  'frames': [
    {
      'at': 0,
      'rows': ['FIRST $cols'],
      'label': null,
    },
    {
      'at': 400,
      'rows': ['LAST $cols'],
      'label': null,
    },
  ],
});

class HeldHost extends FakeHost {
  final pending = <Completer<String?>>[];

  @override
  Future<String?> recording(String file) {
    fetched.add(file);
    final result = Completer<String?>();
    pending.add(result);
    return result.future;
  }
}

Future<void> seek(WidgetTester t, String text) async {
  await t.press('home');
  for (var i = 0; i < 250 && !t.screen.text.contains(text); i++) {
    await t.press('down');
  }
  expect(t.screen, shows(text));
}

void main() {
  group('CHD-638 tester: home request and playback lifetime', () {
    for (final stale in [null, 'invalid JSON', recording(120, 36)]) {
      testWidgets('replaced watch cannot autoplay a newer request: $stale', (
        t,
      ) async {
        final host = HeldHost();
        addTearDown(host.popped.close);
        await t.pumpWidget(Site(host: host), size: const Size(192, 56));
        await t.press('w');
        await t.resize(const Size(120, 40));
        await t.press('w');
        await t.resize(const Size(52, 52));
        host.pending[2].complete(recording(48, 32));
        await t.pump();
        host.pending[1].complete(stale);
        host.pending[0].complete(stale);
        await t.pump();
        await seek(t, 'LAST 48');
        expect(t.screen, shows('W PLAYS'));
        expect(t.screen, isNot(shows('FIRST 48')));
        expect(t.screen, isNot(shows("COULDN'T LOAD")));
        expect(host.fetched, [
          'edit.120x36.rec.json',
          'edit.80x20.rec.json',
          'edit.48x32.rec.json',
        ]);
      });
    }

    testWidgets('removal before a watched request returns ignores its answer', (
      t,
    ) async {
      final host = HeldHost();
      addTearDown(host.popped.close);
      await t.pumpWidget(Site(host: host), size: const Size(52, 52));
      await t.press('w');
      await t.pumpWidget(Text('removed'));
      host.pending.single.complete(recording(48, 32));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(t.screen.text, 'removed');
      expect(host.popped.hasListener, isFalse);
      expect(host.pushed, isEmpty);
      expect(t.exitRequested, isFalse);
    });

    for (final size in const [
      Size(192, 56),
      Size(120, 40),
      Size(80, 24),
      Size(52, 52),
    ]) {
      testWidgets('1000 watches settle, pause survives help, removal stops '
          'playback at $size', (t) async {
        final host = HeldHost();
        addTearDown(host.popped.close);
        await t.pumpWidget(Site(host: host), size: size);
        host.pending.single.complete(recording(48, 32));
        await t.pump();
        for (var n = 0; n < 1000; n++) {
          t.host.handleKey(const KeyEvent('w'));
        }
        await t.pump();
        expect(t.screen, shows('FIRST 48'));
        expect(host.fetched, hasLength(1));
        await t.press('f1');
        await t.press('f1');
        await t.press('space');
        await t.pump(const Duration(milliseconds: 500));
        await seek(t, 'FIRST 48');
        expect(t.screen, shows('W PLAYS'));
        await t.press('w');
        await t.pumpWidget(Text('removed'));
        await t.pump(const Duration(milliseconds: 500));
        expect(t.screen.text, 'removed');
        expect(host.popped.hasListener, isFalse);
      });
    }
  });
}
