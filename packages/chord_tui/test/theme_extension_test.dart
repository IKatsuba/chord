import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

class _Badge extends ThemeExtension<_Badge> {
  const _Badge(this.value);
  final String value;
  @override
  bool operator ==(Object other) => other is _Badge && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

class _SpecialBadge extends _Badge {
  const _SpecialBadge(super.value);
}

class _Other extends ThemeExtension<_Other> {
  const _Other();
}

class _Reader extends StatelessWidget {
  const _Reader(this.read);
  final void Function(ThemeData) read;
  @override
  Widget build(BuildContext context) {
    final data = Theme.of(context);
    read(data);
    return Text(data.extension<_Badge>()?.value ?? 'missing');
  }
}

void main() {
  test('theme extensions are looked up by declared type', () {
    final theme = ThemeData.dark().copyWith(
      extensions: [const _SpecialBadge('special'), const _Other()],
    );
    expect(theme.extension<_Badge>()!.value, 'special');
    expect(theme.extension<_Other>(), isA<_Other>());
    expect(theme.extensions.keys, containsAll([_Badge, _Other]));
    expect(theme.extensions.keys, isNot(contains(_SpecialBadge)));
  });
  test('a missing theme extension returns null', () {
    expect(ThemeData.dark().extension<_Badge>(), isNull);
  });
  test('duplicate extension types are rejected', () {
    expect(
      () => ThemeData.dark().copyWith(
        extensions: [const _Badge('one'), const _Badge('two')],
      ),
      throwsArgumentError,
    );
    expect(
      () => ThemeData.dark().copyWith(
        extensions: [const _Badge('one'), const _SpecialBadge('two')],
      ),
      throwsArgumentError,
    );
  });
  test('theme extensions snapshot input and expose an unmodifiable map', () {
    final values = <ThemeExtension<dynamic>>[const _Badge('kept')];
    final theme = ThemeData(brightness: Brightness.dark, extensions: values);
    values.clear();
    expect(theme.extension<_Badge>()!.value, 'kept');
    expect(() => theme.extensions.clear(), throwsUnsupportedError);
    expect(
      () => theme.extensions[_Badge] = const _Badge('changed'),
      throwsUnsupportedError,
    );
  });
  test('copyWith preserves replaces and clears extensions', () {
    final theme = ThemeData.dark().copyWith(
      extensions: [const _Badge('one'), const _Other()],
    );
    expect(
      theme.copyWith(accent: Style.bold).extension<_Badge>()!.value,
      'one',
    );
    final replacement = theme.copyWith(extensions: [const _Badge('two')]);
    expect(replacement.extension<_Badge>()!.value, 'two');
    expect(replacement.extension<_Other>(), isNull);
    expect(theme.copyWith(extensions: []).extensions, isEmpty);
  });
  test('theme equality and hash include extensions independent of order', () {
    final one = ThemeData.dark().copyWith(
      extensions: [const _Badge('same'), const _Other()],
    );
    final two = ThemeData.dark().copyWith(
      extensions: [const _Other(), const _Badge('same')],
    );
    expect(one, two);
    expect(one.hashCode, two.hashCode);
    expect(one, isNot(ThemeData.dark()));
    expect(
      one,
      isNot(
        one.copyWith(extensions: [const _Badge('different'), const _Other()]),
      ),
    );
  });
  testWidgets('an extension-only theme change rebuilds dependent widgets', (
    t,
  ) async {
    final theme = ValueNotifier(
      ThemeData.dark().copyWith(extensions: [const _Badge('one')]),
    );
    var builds = 0;
    final reader = _Reader((_) => builds++);
    await t.pumpWidget(
      ListenableBuilder(
        listenable: theme,
        builder: (_) => Theme(data: theme.value, child: reader),
      ),
    );
    final initial = builds;
    theme.value = theme.value.copyWith(extensions: [const _Badge('two')]);
    await t.pump();
    expect(builds, initial + 1);
    expect(t.screen, shows('two'));
    t.dispose();
    theme.dispose();
  });
  testWidgets('equal extension collections do not notify dependents', (
    t,
  ) async {
    final theme = ValueNotifier(
      ThemeData.dark().copyWith(
        extensions: [const _Badge('same'), const _Other()],
      ),
    );
    var builds = 0;
    final reader = _Reader((_) => builds++);
    await t.pumpWidget(
      ListenableBuilder(
        listenable: theme,
        builder: (_) => Theme(data: theme.value, child: reader),
      ),
    );
    final initial = builds;
    theme.value = theme.value.copyWith(
      extensions: [const _Other(), const _Badge('same')],
    );
    await t.pump();
    expect(builds, initial);
    t.dispose();
    theme.dispose();
  });
  testWidgets('the nearest theme does not merge ancestor extensions', (
    t,
  ) async {
    await t.pumpWidget(
      Theme(
        data: ThemeData.dark().copyWith(extensions: [const _Badge('outer')]),
        child: Theme(
          data: ThemeData.light().copyWith(extensions: [const _Other()]),
          child: _Reader((theme) {
            expect(theme.extension<_Badge>(), isNull);
            expect(theme.extension<_Other>(), isNotNull);
          }),
        ),
      ),
    );
    expect(t.screen, shows('missing'));
  });
  test(
    'dark light plain and fallback factories keep empty extensions by default',
    () {
      for (final theme in [
        ThemeData.dark(),
        ThemeData.light(),
        ThemeData.plain(),
        ThemeData.fallback(),
      ]) {
        expect(theme.extensions, isEmpty);
      }
    },
  );
  group('tester U11a extension registry boundaries', () {
    test(
      'a lazy input is snapshotted once and copied registries stay independent',
      () {
        var reads = 0;
        Iterable<ThemeExtension<dynamic>> values() sync* {
          reads++;
          yield const _SpecialBadge('first');
          yield const _Other();
        }

        final original = ThemeData(
          brightness: Brightness.light,
          extensions: values(),
        );
        expect(reads, 1);
        final replacement = original.copyWith(
          extensions: [const _Badge('second')],
        );
        expect(original.extension<_Badge>()!.value, 'first');
        expect(replacement.extension<_Badge>()!.value, 'second');
        expect(replacement.extension<_Other>(), isNull);
        expect(original.copyWith().extensions, original.extensions);
        expect(reads, 1);
        expect(
          () => replacement.extensions.remove(_Badge),
          throwsUnsupportedError,
        );
      },
    );

    test('same declared slot is duplicate in either subclass order', () {
      for (final extensions in <List<ThemeExtension<dynamic>>>[
        [const _SpecialBadge('special'), const _Badge('base')],
        [const _Badge('base'), const _SpecialBadge('special')],
      ]) {
        expect(
          () => ThemeData(brightness: Brightness.dark, extensions: extensions),
          throwsArgumentError,
        );
      }
      final base = ThemeData.dark().copyWith(
        extensions: [const _Badge('same')],
      );
      final specialized = ThemeData.dark().copyWith(
        extensions: [const _SpecialBadge('same')],
      );
      expect(base, specialized);
      expect(base.hashCode, specialized.hashCode);
    });

    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'extension bursts settle once and detach with live stream at $size',
        (t) async {
          final theme = ValueNotifier(
            ThemeData.dark().copyWith(extensions: [const _Badge('start')]),
          );
          final stream = StreamController<ThemeData>(sync: true);
          final subscription = stream.stream.listen(
            (value) => theme.value = value,
          );
          addTearDown(() async {
            await subscription.cancel();
            await stream.close();
            theme.dispose();
          });
          var builds = 0;
          final reader = _Reader((_) => builds++);
          await t.pumpWidget(
            ListenableBuilder(
              listenable: theme,
              builder: (_) => Theme(data: theme.value, child: reader),
            ),
            size: size,
          );
          final initial = builds;
          for (var i = 0; i < 1000; i++) {
            stream.add(
              theme.value.copyWith(extensions: [_Badge('界🙂e\u0301 $i')]),
            );
          }
          await t.pump();
          expect(builds, initial + 1);
          expect(t.screen, shows('界🙂e\u0301 999'));
          await t.resize(const Size(0, 0));
          await t.resize(const Size(1, 1));
          await t.resize(size);
          expect(t.screen, shows('界🙂e\u0301 999'));
          await t.pumpWidget(Text('removed'));
          final before = builds;
          stream.add(theme.value.copyWith(extensions: [const _Badge('late')]));
          await t.pump();
          expect(builds, before);
          expect(t.screen, shows('removed'));
        },
      );
    }
  });
}
