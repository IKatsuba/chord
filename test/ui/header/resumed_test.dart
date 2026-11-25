import 'package:chord/session/sessions.dart';
import 'package:chord/ui/header/compact.dart';
import 'package:chord/ui/header/resumed.dart';
import 'package:chord/ui/transcript/selection.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'opening labels preserve original child/title/prompt precedence and age',
    () {
      const now = 946771200000;
      expect(
        resumedHeader(const Resume(sessionId: 'a', cwd: '.'), now).text,
        'resumed',
      );
      expect(
        resumedHeader(
          const Resume(
            sessionId: 'a',
            cwd: '.',
            name: 'child',
            prompt: 'parent',
          ),
          now,
        ).text,
        'resumed · child',
      );
      final titled = resumedHeader(
        const Resume(
          sessionId: 'a',
          cwd: '.',
          title: 'Actual title',
          name: 'child',
          prompt: 'parent',
          lastUsedAt: 946684800000.75,
        ),
        now,
      );
      expect(titled.text, 'resumed · yesterday · child · Actual title');
      expect(titled.wrap, isTrue);
      final fallback = resumedHeader(
        const Resume(sessionId: 'a', cwd: '.'),
        now,
        firstPrompt: '<message from="main">\nWork here\n</message>',
      );
      expect(fallback.text, 'resumed · Work here');
      expect(fallback.wrap, isFalse);
    },
  );
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'agent title wraps but fallback cuts; selection uses same text $size',
      (t) async {
        final title = List.filled(12, 'Saved title 界😀').join(' ');
        final facts = ResumedHeader('resumed · yesterday · $title', wrap: true);
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
            selectionSource: source,
          ),
          size: size,
        );
        expect(t.screen, shows('resumed · yesterday'));
        expect(
          t.screen.lines.where((line) => line.contains('Saved title')).length,
          greaterThan(1),
        );
        expect(
          t.screen.lines.where((line) => line.contains('shortcuts')).length,
          1,
        );
        await t.pumpWidget(
          CompactHeader(
            version: 'test',
            agent: 'fake',
            directory: 'project',
            resumed: ResumedHeader(facts.text, wrap: false),
          ),
          size: size,
        );
        expect(
          t.screen.lines.where((line) => line.contains('Saved title')).length,
          1,
        );
      },
    );
  }
}
