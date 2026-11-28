import 'dart:async';
import 'dart:convert';

import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'fake_host.dart';

/// A host whose recording fetches return when the test says.
class _SlowHost extends FakeHost {
  _SlowHost() : super('/chord/permission');

  final pending = <(String, Completer<String?>)>[];

  @override
  Future<String?> recording(String file) {
    final answer = Completer<String?>();
    pending.add((file, answer));
    return answer.future;
  }
}

String _recording(int cols, int rows, String first) => jsonEncode({
  'version': 1,
  'cols': cols,
  'rows': rows,
  'frames': [
    {
      'at': 0,
      'rows': [first],
      'label': null,
    },
  ],
});

final _big = _recording(120, 36, 'big recording');
final _small = _recording(80, 20, 'small recording');

const _names = ['permission'];

void main() {
  testWidgets('a resize to another size loads afresh, saying so', (t) async {
    final host = _SlowHost();
    await t.pumpWidget(
      Site(host: host, recordings: _names),
      size: const Size(122, 47),
    );
    host.pending.single.$2.complete(_big);
    await t.pump();
    expect(t.screen, shows('big recording'));
    await t.resize(const Size(82, 31));
    expect(t.screen, shows('LOADING PERMISSION…'));
    expect(t.screen, isNot(shows('big recording')));
    expect(host.pending.last.$1, 'permission.80x20.rec.json');
    host.pending.last.$2.complete(_small);
    await t.pump();
    expect(t.screen, shows('small recording'));
  });

  testWidgets('a retry after a failure says it is loading', (t) async {
    final host = _SlowHost();
    await t.pumpWidget(
      Site(host: host, recordings: _names),
      size: const Size(82, 31),
    );
    host.pending.single.$2.complete(null);
    await t.pump();
    expect(t.screen, shows("COULDN'T LOAD PERMISSION"));
    await t.resize(const Size(122, 47));
    expect(t.screen, shows('LOADING PERMISSION…'));
    host.pending.last.$2.complete(_big);
    await t.pump();
    expect(t.screen, shows('big recording'));
  });

  testWidgets('an older fetch for the same file never wins', (t) async {
    final host = _SlowHost();
    await t.pumpWidget(
      Site(host: host, recordings: _names),
      size: const Size(122, 47),
    );
    await t.resize(const Size(82, 31));
    await t.resize(const Size(122, 47));
    final [a, b, c] = host.pending;
    expect(
      [a.$1, b.$1, c.$1],
      [
        'permission.120x36.rec.json',
        'permission.80x20.rec.json',
        'permission.120x36.rec.json',
      ],
    );
    c.$2.complete(_big);
    await t.pump();
    expect(t.screen, shows('big recording'));
    a.$2.complete(_recording(120, 36, 'stale recording'));
    b.$2.complete(_small);
    await t.pump();
    expect(t.screen, shows('big recording'));
    expect(t.screen, isNot(shows('stale recording')));
    expect(t.screen, isNot(shows('small recording')));
  });

  testWidgets('a fetch that returns after the page went does nothing', (
    t,
  ) async {
    final host = _SlowHost();
    await t.pumpWidget(
      Site(host: host, recordings: _names),
      size: const Size(122, 47),
    );
    host.popped.add('/chord');
    await t.pump();
    expect(t.screen, shows('01 / THE APP'));
    host.pending.single.$2.complete(_big);
    await t.pump();
    expect(t.screen, isNot(shows('big recording')));
  });
}
