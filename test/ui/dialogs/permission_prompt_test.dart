import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/permission_review.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/dialogs/permission_prompt.dart';
import 'package:chord/ui/dialogs/permission_scroll.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/permission.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'standalone held fixture attends through its outer action at $size',
      (t) async {
        await t.pumpWidget(permissionPreview('held'), size: size);
        expect(t.screen, shows('ctrl+x a to answer'));
        await t.press('ctrl+x a');
        expect(t.screen, shows('Esc to reject'));
        expect(t.screen, shows('❯ 1. Allow once'));
        await t.press('2');
        expect(t.screen, shows('Answer: always'));
      },
    );
    testWidgets(
      'permission choices wrap at both ends for arrows and j k at $size',
      (t) async {
        final scroll = PermissionScroll();
        final picks = <String>[];
        await t.pumpWidget(
          PermissionPrompt(
            wait: permissionFixture(),
            windowRows: size.height,
            maxRows: size.height,
            scroll: scroll,
            onChoose: picks.add,
            onReject: () {},
          ),
          size: size,
        );
        await t.press('up enter down enter k enter j enter');
        expect(picks, ['deny', 'allow', 'deny', 'allow']);
        t.dispose();
        scroll.dispose();
      },
    );
    for (final mode in ['diff', 'review', 'failed']) {
      testWidgets(
        '$mode keeps answers and hint below scrolling request at $size',
        (t) async {
          final scroll = PermissionScroll();
          final picks = <String>[];
          var rejected = 0;
          await t.pumpWidget(
            Actions(
              bindings: [
                Binding(
                  'pageup',
                  'Read request above',
                  () => scroll.step(ScrollStep.pageUp),
                ),
                Binding(
                  'pagedown',
                  'Read request below',
                  () => scroll.step(ScrollStep.pageDown),
                ),
              ],
              child: Column(
                children: [
                  PermissionPrompt(
                    wait: permissionFixture(mode: mode),
                    windowRows: size.height,
                    maxRows: size.height - 1,
                    scroll: scroll,
                    onChoose: picks.add,
                    onReject: () => rejected++,
                  ),
                  Text('AFTER'),
                ],
              ),
            ),
            size: size,
          );
          expect(t.screen, shows('Write notes.txt'));
          expect(t.screen, shows('1. Allow once'));
          expect(t.screen, shows('3. Deny'));
          expect(
            t.screen,
            shows('Esc to reject · denied by itself in 5 minutes'),
          );
          expect(t.screen, shows('AFTER'));
          if (mode == 'review') {
            expect(t.screen, shows('The safety review held this:'));
            expect(t.screen, shows('This command could overwrite files'));
          } else if (mode == 'failed') {
            expect(t.screen, shows('The safety review could not run'));
            expect(t.screen, shows('yourself, or deny it.'));
          } else {
            expect(t.screen, shows('Do you want to proceed?'));
          }
          expect(t.screen, shows('pagedown to scroll'));
          await t.press('pagedown');
          expect(scroll.top, greaterThan(0));
          expect(t.screen, shows('pageup to scroll'));
          for (var i = 0; i < 30; i++) {
            await t.press('pagedown');
          }
          expect(t.screen, shows('proposed line 60'));
          expect(t.screen, shows('Write notes.txt'));
          expect(t.screen, shows('3. Deny'));
          await t.press('up down enter');
          expect(picks, ['allow']);
          await t.press('3 esc');
          expect(picks, ['allow', 'deny']);
          expect(rejected, 1);
          t.dispose();
          scroll.dispose();
        },
      );
    }
    testWidgets(
      'held request names between turns and activates without losing text at $size',
      (t) async {
        final held = ValueNotifier(true);
        final scroll = PermissionScroll();
        final node = FocusNode();
        final picks = <String>[];
        await t.pumpWidget(
          ListenableBuilder(
            listenable: held,
            builder: (context) => PermissionPrompt(
              wait: permissionFixture(mode: 'held'),
              windowRows: size.height,
              maxRows: size.height,
              scroll: scroll,
              focusNode: node,
              between: true,
              held: held.value,
              onChoose: picks.add,
              onReject: () {},
            ),
          ),
          size: size,
        );
        expect(t.screen, shows('main asks · between turns'));
        expect(t.screen, shows('ctrl+x a to answer'));
        expect(t.screen, isNot(shows('❯')));
        expect(t.screen, isNot(shows('pagedown to scroll')));
        await t.press('1 down enter');
        expect(picks, isEmpty);
        held.value = false;
        await t.pump();
        expect(node.hasFocus, isFalse);
        node.requestFocus();
        await t.pump();
        await t.press('2');
        expect(picks, ['always']);
        expect(t.screen, shows('Esc to reject'));
        t.dispose();
        held.dispose();
        scroll.dispose();
        node.dispose();
      },
    );

    testWidgets(
      'one-row request counts hidden rows beside pinned title at $size',
      (t) async {
        final scroll = PermissionScroll();
        final wait = PermissionWait(
          'one',
          title: 'Run a long title for a command',
          rawInput: 'arg\n' * 30,
          options: permissionFixture().options,
          review: const PermissionReview('caution', 'Review this.'),
        );
        await t.pumpWidget(
          PermissionPrompt(
            wait: wait,
            windowRows: size.height,
            maxRows: 14,
            scroll: scroll,
            onChoose: (_) {},
            onReject: () {},
          ),
          size: size,
        );
        expect(t.screen, shows('lines below'));
        expect(t.screen, isNot(shows('to scroll')));
        expect(t.screen, shows('Review this.'));
        expect(t.screen, shows('3. Deny'));
        expect(t.screen, shows('Esc to reject'));
        t.dispose();
        scroll.dispose();
      },
    );
  }
  for (final width in [80, 28]) {
    testWidgets('long full numbered labels wrap at the number column in $width', (
      t,
    ) async {
      final scroll = PermissionScroll();
      const label =
          'Yes, and do not ask again for files - write_file commands in this project';
      final wait = PermissionWait(
        'long',
        title: 'Write files',
        options: [
          acp.PermissionOption.fromJson({
            'optionId': 'allow',
            'name': label,
            'kind': 'allow_once',
          }),
          acp.PermissionOption.fromJson({
            'optionId': 'deny',
            'name': 'No',
            'kind': 'reject_once',
          }),
        ],
      );
      final lines = TextLayout.compute(
        const TextSpan('1. $label'),
        maxWidth: width - 6,
      ).lines.map((row) => row.map((g) => g.text).join()).toList();
      await t.pumpWidget(
        Column(
          children: [
            PermissionPrompt(
              wait: wait,
              windowRows: 40,
              maxRows: 39,
              scroll: scroll,
              onChoose: (_) {},
              onReject: () {},
            ),
            Text('AFTER'),
          ],
        ),
        size: Size(width, 40),
      );
      final first = t.screen.lines.indexWhere(
        (line) => line.contains(lines.first),
      );
      expect(first, greaterThan(0));
      for (var i = 1; i < lines.length; i++) {
        expect(t.screen.lines[first + i].startsWith('│   ${lines[i]}'), isTrue);
      }
      expect(t.screen, shows('2. No'));
      expect(t.screen, shows('AFTER'));
      t.dispose();
      scroll.dispose();
    });
  }
  testWidgets('narrow pinned hidden count uses original middle CUT', (t) async {
    final scroll = PermissionScroll();
    await t.pumpWidget(
      PermissionPrompt(
        wait: const PermissionWait(
          'cut',
          title: 'A long title',
          rawInput:
              'one\n'
              'two\n'
              'three\n'
              'four\n',
        ),
        windowRows: 40,
        maxRows: 0,
        scroll: scroll,
        onChoose: (_) {},
        onReject: () {},
      ),
      size: const Size(18, 40),
    );
    expect(t.screen, shows('...'));
    expect(t.screen, shows('below'));
    t.dispose();
    scroll.dispose();
  });
  // CTUI-89: as the save box, each wrapped choice is as tall as it is
  // drawn, so at 40 columns none is pushed out of the box.
  for (final size in [const Size(40, 24), const Size(40, 40)]) {
    testWidgets('long choices wrap and all stay in the box at $size', (
      t,
    ) async {
      final scroll = PermissionScroll();
      await t.pumpWidget(
        PermissionPrompt(
          wait: permissionFixture(mode: 'long'),
          windowRows: size.height,
          maxRows: size.height,
          scroll: scroll,
          onChoose: (_) {},
          onReject: () {},
        ),
        size: size,
      );
      for (final start in [
        '❯ 1. Allow once,',
        '  2. Always allow,',
        '  3. Deny,',
      ]) {
        expect(
          t.screen.lines.where((line) => line.contains(start)),
          hasLength(1),
          reason: t.screen.text,
        );
      }
      // Every label ends in the same words, so each choice's last row is
      // found by count, and Deny's own rows, after its first, by place.
      final lines = t.screen.lines;
      expect(
        lines.where((line) => line.contains('this project')),
        hasLength(3),
        reason: t.screen.text,
      );
      final deny = lines.indexWhere((line) => line.contains('  3. Deny,'));
      final rest = lines
          .skip(deny)
          .takeWhile((line) => !line.startsWith('╰'))
          .join(' ');
      expect(
        rest.replaceAll(RegExp(r'[│ ]+'), ' '),
        contains(
          '3. Deny, and do not ask again for files - write_file commands in '
          'this project',
        ),
        reason: t.screen.text,
      );
      t.dispose();
      scroll.dispose();
    });
  }
}
