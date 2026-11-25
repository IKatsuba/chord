import 'dart:async';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/state.dart';
import 'package:chord/ui/prompt/prompt.dart';
import 'package:chord/ui/prompt/search.dart' show emptySearch;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import 'selection_window_test.dart';
import 'code_pick_window_test.dart' show reply, pressBounded;

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.pump();
  }
}

class _GeometryChurn extends StatefulWidget {
  const _GeometryChurn({
    required this.enabled,
    required this.child,
    this.duringLayout,
  });
  final void Function()? duringLayout;
  final bool enabled;
  final Widget child;
  @override
  State<_GeometryChurn> createState() => _GeometryChurnState();
}

class _GeometryChurnState extends State<_GeometryChurn> {
  @override
  Widget build(BuildContext context) {
    if (widget.enabled) {
      context.owner.afterLayout(() {
        if (mounted) setState(() {});
      });
    }
    final callback = widget.duringLayout;
    if (callback != null) {
      context.owner.afterLayout(() {
        if (mounted && widget.duringLayout == callback) callback();
      });
    }
    return widget.child;
  }
}

Future<void> flushResult() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'file finder overlays rows, quotes full literal pick and keeps cursor focus $size',
      (t) async {
        final c = selectionConnection();
        addTearDown(c.close);
        final paths = [
          'space name.md',
          ...List.generate(
            20,
            (i) => 'src/file_${i.toString().padLeft(2, '0')}.dart',
          ),
        ];
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: c,
            walkFiles: (cwd, {cancellationToken}) async => paths,
          ),
          size: size,
        );
        final focus = t.focusManager.primaryFocus;
        await t.type('@');
        await settle(t);
        expect(t.screen, shows('space name.md'));
        expect(t.screen, shows('src/file_00.dart'));
        expect(t.focusManager.primaryFocus, same(focus));
        await pressBounded(t, 'tab');
        expect(c.app.value.draft, '@"space name.md" ');
        expect(c.app.value.cursor, '@"space name.md" '.length);
        expect(t.screen, isNot(shows('src/file_00.dart')));
        expect(t.focusManager.primaryFocus, same(focus));
      },
    );
    testWidgets(
      'agents freeze reachable snapshot, empty state and no-match remain unselectable $size',
      (t) async {
        final c = selectionConnection();
        addTearDown(c.close);
        final recipients = [
          const MentionRecipient('parser'),
          const MentionRecipient('bugfix 2'),
          const MentionRecipient('parser'),
        ];
        final widget = TranscriptWindow(
          launch: selectionLaunch,
          connection: c,
          recipients: recipients,
          walkFiles: (cwd, {cancellationToken}) async => [],
        );
        recipients.add(const MentionRecipient('late'));
        await t.pumpWidget(widget, size: size);
        await t.type('@@');
        await settle(t);
        expect(t.screen, shows('parser'));
        expect(t.screen, shows('bugfix 2'));
        expect(t.screen, isNot(shows('late')));
        await pressBounded(t, 'down tab');
        expect(c.app.value.draft, '@@"bugfix 2" ');
        await t.press('ctrl+c');
        await t.type('@@zzz');
        await settle(t);
        expect(t.screen, shows('No matching agents'));
        await t.press('tab');
        expect(c.app.value.draft, '@@zzz');
        await t.press('esc');
        expect(c.app.value.draft, '@@zzz');
        expect(t.screen, isNot(shows('No matching agents')));
        await t.pumpWidget(
          TranscriptWindow(launch: selectionLaunch, connection: c),
          size: size,
        );
        await t.type('@@');
        await settle(t);
        expect(t.screen, shows('No agents to mention'));
        await t.press('tab');
        expect(c.app.value.draft, '@@');
      },
    );
    testWidgets(
      'overflowing finder wheel owns original box and keyboard reveals clamped highlight $size',
      (t) async {
        final c = selectionConnection([
          for (var i = 0; i < 80; i++) reply('history $i'),
        ]);
        addTearDown(c.close);
        final paths = List.generate(
          40,
          (i) => 'file_${i.toString().padLeft(2, '0')}.md',
        );
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: c,
            walkFiles: (cwd, {cancellationToken}) async => paths,
          ),
          size: size,
        );
        final offset = c.app.value.scroll.offset;
        await t.type('@');
        await settle(t);
        final at = cellOf(t, 'file_00.md');
        for (var i = 0; i < 4; i++) {
          await t.mouse(
            MouseEvent(
              MouseEventKind.wheel,
              position: at,
              scrollDelta: const Offset(0, 1),
            ),
          );
        }
        expect(c.app.value.scroll.offset, offset);
        expect(t.screen, isNot(shows('file_00.md')));
        await pressBounded(t, List.filled(15, 'down').join(' '));
        await settle(t);
        expect(t.screen, shows('file_15.md'));
        await t.press('tab');
        expect(c.app.value.draft, '@file_15.md ');
      },
    );
    for (final zero in [Size(size.width, 5), Size(0, size.height)]) {
      testWidgets(
        'pending wait drops at $zero and never replays when room returns $size',
        (t) async {
          final c = selectionConnection();
          addTearDown(c.close);
          final pending = Completer<List<String>?>();
          await t.pumpWidget(
            TranscriptWindow(
              launch: selectionLaunch,
              connection: c,
              walkFiles: (cwd, {cancellationToken}) async => ['alpha'],
              matchMentions: (names, q) =>
                  q.isEmpty ? Future.value(names) : pending.future,
            ),
            size: size,
          );
          await t.type('@');
          await settle(t);
          await t.type('a');
          await settle(t);
          await t.press('tab');
          expect(c.app.value.draft, '@a');
          await t.resize(zero);
          await settle(t);
          await t.resize(size);
          await settle(t);
          pending.complete(['alpha']);
          await settle(t);
          expect(c.app.value.draft, '@a');
        },
      );
    }

    testWidgets(
      'long literal filename inserts fully with grapheme end cursor $size',
      (t) async {
        final c = selectionConnection();
        addTearDown(c.close);
        final name = '🙂e\u0301 ${'long name ' * 20}.md';
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: c,
            walkFiles: (cwd, {cancellationToken}) async => [name],
          ),
          size: size,
        );
        await t.type('@');
        await settle(t);
        expect(t.screen, isNot(shows(name)));
        await t.press('tab');
        expect(c.app.value.draft, '@"$name" ');
        expect(c.app.value.cursor, endOf('@"$name" '));
      },
    );
    testWidgets(
      'replacement roster drops old pending pick and disposal rejects late results $size',
      (t) async {
        final c = selectionConnection();
        addTearDown(c.close);
        final old = Completer<List<String>?>(),
            current = Completer<List<String>?>();
        Future<List<String>?> match(List<String> names, String query) =>
            query.isEmpty
            ? Future.value(names)
            : names.first == 'parser'
            ? old.future
            : current.future;
        Future<List<String>> walk(String cwd, {cancellationToken}) async => [];
        final screen = ValueNotifier<Widget>(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: c,
            walkFiles: walk,
            matchMentions: match,
            recipients: const [MentionRecipient('parser')],
          ),
        );
        addTearDown(screen.dispose);
        await t.pumpWidget(
          ListenableBuilder(listenable: screen, builder: (_) => screen.value),
          size: size,
        );
        await t.type('@@a');
        await settle(t);
        await t.press('tab');
        screen.value = TranscriptWindow(
          launch: selectionLaunch,
          connection: c,
          walkFiles: walk,
          matchMentions: match,
          recipients: const [MentionRecipient('beta')],
        );
        await settle(t);
        old.complete(['parser']);
        await settle(t);
        current.complete(['beta']);
        await settle(t);
        expect(c.app.value.draft, '@@a');
        expect(t.screen, shows('beta'));
        expect(t.screen, isNot(shows('parser')));
        await t.press('tab');
        expect(c.app.value.draft, '@@beta ');
        final late = Completer<List<String>?>();
        screen.value = TranscriptWindow(
          launch: selectionLaunch,
          connection: c,
          walkFiles: walk,
          matchMentions: (names, q) =>
              q.isEmpty ? Future.value(names) : late.future,
          recipients: const [MentionRecipient('gamma')],
        );
        await settle(t);
        await t.press('ctrl+c');
        await t.type('@@g');
        await settle(t);
        await t.press('tab');
        screen.value = Text('unmounted');
        await settle(t);
        late.complete(['gamma']);
        await settle(t);
        expect(t.screen.text, 'unmounted');
      },
    );

    testWidgets(
      'empty pending surface preserves transcript paint and owns only current positive-room wait $size',
      (t) async {
        final c = selectionConnection([
          for (var i = 0; i < 60; i++) reply('history $i'),
          reply('```ts\nlast code\n```'),
        ]);
        addTearDown(c.close);
        final noMatch = Completer<List<String>?>(),
            pending = Completer<List<String>?>();
        await t.pumpWidget(
          TranscriptWindow(
            launch: selectionLaunch,
            connection: c,
            walkFiles: (cwd, {cancellationToken}) async => ['zero.dart'],
            matchMentions: (names, q) => q.isEmpty
                ? Future.value(names)
                : q == 'zz'
                ? noMatch.future
                : pending.future,
          ),
          size: size,
        );
        await t.type('@zz');
        await settle(t);
        noMatch.complete([]);
        await settle(t);
        final border = t.screen.lines.indexWhere((line) => line.contains('╭'));
        expect(border, greaterThan(1));
        final before = t.screen.lines.take(border - 1).toList();
        expect(before.last.trim(), isNotEmpty);
        final focus = t.focusManager.primaryFocus;
        await t.press('backspace');
        await settle(t);
        expect(c.app.value.draft, '@z');
        expect(t.screen.lines.take(border - 1), before);
        expect(t.focusManager.primaryFocus, same(focus));
        final offset = c.app.value.scroll.offset;
        await t.mouse(
          MouseEvent(
            MouseEventKind.wheel,
            position: Offset(2, border - 2),
            scrollDelta: const Offset(0, -1),
          ),
        );
        expect(c.app.value.scroll.offset, offset - 1);
        await t.press('tab');
        expect(c.app.value.draft, '@z');
        pending.complete(['zero.dart']);
        await settle(t);
        expect(c.app.value.draft, '@zero.dart ');
      },
    );

    for (final dirty in [
      'resize',
      'constraints',
      'unlink',
      'replacement',
      'exhausted',
      'dispose',
    ]) {
      testWidgets(
        'async pending pick synchronizes $dirty without a frame and never replays $size',
        (t) async {
          final c = selectionConnection();
          addTearDown(c.close);
          final pending = Completer<List<String>?>();
          final height = ValueNotifier(size.height),
              churn = ValueNotifier(false);
          addTearDown(height.dispose);
          addTearDown(churn.dispose);
          final window = TranscriptWindow(
            launch: selectionLaunch,
            connection: c,
            walkFiles: (cwd, {cancellationToken}) async => ['alpha'],
            matchMentions: (names, q) =>
                q.isEmpty ? Future.value(names) : pending.future,
          );
          final intercept = ValueNotifier<void Function()?>(null);
          addTearDown(intercept.dispose);
          final currentWindow = ValueNotifier<Widget>(window);
          addTearDown(currentWindow.dispose);
          await t.pumpWidget(
            ListenableBuilder(
              listenable: intercept,
              builder: (_) => ListenableBuilder(
                listenable: currentWindow,
                builder: (_) => ListenableBuilder(
                  listenable: height,
                  builder: (_) => ListenableBuilder(
                    listenable: churn,
                    builder: (_) => _GeometryChurn(
                      enabled: churn.value,
                      duringLayout: intercept.value,
                      child: dirty == 'constraints'
                          ? Column(
                              children: [
                                SizedBox(
                                  height: height.value,
                                  child: currentWindow.value,
                                ),
                                const Expanded(child: SizedBox()),
                              ],
                            )
                          : currentWindow.value,
                    ),
                  ),
                ),
              ),
            ),
            size: size,
          );
          await t.type('@a');
          await settle(t);
          await t.press('tab');
          void observer() {
            intercept.value = null;
            if (dirty == 'replacement') {
              currentWindow.value = TranscriptWindow(
                launch: selectionLaunch,
                connection: c,
                walkFiles: (cwd, {cancellationToken}) async => ['fresh'],
                matchMentions: (names, q) async => [],
              );
            } else if (dirty == 'dispose') {
              t.host.dispose();
            } else {
              t.host.handleKey(KeyCombo.parse('x').toEvent());
            }
          }

          final originalApp = c.app.value;
          switch (dirty) {
            case 'resize':
              t.host.updateSize(Size(size.width, 5));
            case 'constraints':
              height.value = 5;
            case 'unlink':
              // History search puts its own line where the prompt box was.
              c.app.value = AppState(
                start: originalApp.start,
                search: emptySearch,
                draft: originalApp.draft,
                cursor: originalApp.cursor,
              );
            case 'exhausted':
              churn.value = true;
            case 'dispose' || 'replacement':
              intercept.value = observer;
          }
          final passes = t.inputLayoutPasses;
          pending.complete(['alpha']);
          await flushResult();
          expect(c.app.value.draft, '@a');
          expect(t.inputLayoutPasses - passes, lessThanOrEqualTo(2));
          if (dirty == 'dispose') return;
          if (dirty == 'exhausted') {
            expect(t.inputLayoutPasses - passes, 2);
            churn.value = false;
          }
          if (dirty == 'unlink') c.app.value = originalApp;
          height.value = size.height;
          t.host.updateSize(size);
          await settle(t);
          expect(c.app.value.draft, '@a');
        },
      );
    }
  }
}
