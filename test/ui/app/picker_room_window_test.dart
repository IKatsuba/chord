// CTUI-107: /theme and /mcp float in the rows the transcript is given, as
// dimcode's notice does (CTUI-101) and as the original's App.tsx passes
// them the live room: under a tall draft and a tall agent list they fit
// those rows, the header above them and their own last line in sight,
// instead of sizing themselves by the window less five rows and clipping.
import 'package:chord/cli.dart';
import 'package:chord/mcp.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/children.dart';

/// Ten servers, more than fit beside the draft and the list.
final _servers = [
  for (var i = 0; i < 10; i++)
    DefinedServer({
      'name': 'server-$i',
      'command': 'server-$i',
      'args': <Object?>[],
      'env': <Object?>[],
    }, '.mcp.json'),
];

void main() {
  group('tester: live picker room transitions', () {
    for (final (name, open, title, footer) in [
      (
        'theme',
        const ThemePickerOpenedAction(),
        'Theme',
        'Esc to go back to Auto',
      ),
      ('mcp', const McpOpenedAction(), 'MCP servers', 'Esc to close'),
    ]) {
      for (final initial in const [Size(80, 24), Size(120, 40)]) {
        testWidgets(
          '$name retains a tall draft across live resize from $initial',
          (t) async {
            final fixture = childrenFixture(['--many', '--tall', '--tasks']);
            addTearDown(fixture.close);
            final app = fixture.connection.app;
            final draft = List.generate(
              20,
              (i) => 'line $i 界🙂e\u0301',
            ).join('\n');
            await t.pumpWidget(
              TranscriptWindow(
                launch: Launch(
                  name: 'fake',
                  agent: null,
                  agentCommand: 'fake',
                  version: '0.0.1',
                  directory: 'project',
                  mcpServers: _servers,
                ),
                connection: fixture.connection,
              ),
              size: initial,
            );
            await t.paste(draft);
            app.value = reduceWindow(app.value, open);
            await t.pump();
            await t.pump();
            expect(app.value.draft, draft);
            expect(t.screen.text, contains('line 19'));
            for (final size in [
              initial,
              const Size(120, 40),
              const Size(80, 24),
            ]) {
              await t.resize(size);
              await t.pump();
              await t.pump();
              if (size.height >= 24) {
                expect(t.screen.text, contains(footer));
                final heading = t.screen.lines.firstWhere(
                  (row) => row.startsWith('│ $title'),
                );
                expect(cellWidth(heading.trimRight()), size.width);
              }
            }
            expect(t.screen.text, contains(footer));
            await t.press('esc');
            await t.pump();
            expect(t.screen.text, isNot(contains(footer)));
            expect(app.value.draft, draft);
          },
        );
      }
    }
  });

  for (final size in const [Size(80, 24), Size(120, 40)]) {
    for (final (name, open, title, last) in [
      (
        '/theme',
        const ThemePickerOpenedAction(),
        'Theme',
        'Esc to go back to Auto',
      ),
      ('/mcp', const McpOpenedAction(), 'MCP servers', 'Esc to close'),
    ]) {
      testWidgets('$name under a tall draft and agent list fits the '
          "transcript's rows, at $size", (t) async {
        final f = childrenFixture(['--tall', '--tasks']);
        addTearDown(f.close);
        await t.pumpWidget(
          TranscriptWindow(
            launch: Launch(
              name: 'fake',
              agent: null,
              agentCommand: 'fake',
              version: '0.0.1',
              directory: 'project',
              mcpServers: _servers,
            ),
            connection: f.connection,
          ),
          size: size,
        );
        await t.paste(List.generate(20, (i) => 'draft $i 界😀é').join('\n'));
        final app = f.connection.app;
        app.value = reduceWindow(app.value, open);
        await t.pump();
        await t.pump();
        final text = t.screen.text;
        expect(text, contains('chord v0.0.1'), reason: text);
        expect(text, contains(last), reason: text);
        // Its frame spans the window, a tight one with no list too.
        final heading = t.screen.lines.firstWhere(
          (line) => line.startsWith('│ $title'),
        );
        expect(cellWidth(heading.trimRight()), size.width, reason: text);
      });
    }
  }

  // A tight room unmounts the list that had the keys: Esc must still close
  // the picker, as the original's does.
  testWidgets('/theme closes on Esc after a resize takes its list', (t) async {
    final f = childrenFixture(['--many', '--tall', '--tasks']);
    addTearDown(f.close);
    await t.pumpWidget(
      TranscriptWindow(
        launch: const Launch(
          name: 'fake',
          agent: null,
          agentCommand: 'fake',
          version: '0.0.1',
          directory: 'project',
        ),
        connection: f.connection,
      ),
      size: const Size(120, 40),
    );
    await t.paste(List.generate(20, (i) => 'draft $i').join('\n'));
    final app = f.connection.app;
    app.value = reduceWindow(app.value, const ThemePickerOpenedAction());
    await t.pump();
    await t.pump();
    expect(t.screen.text, contains('Enter to keep'));
    await t.resize(const Size(80, 24));
    await t.pump();
    expect(t.screen.text, contains('Esc to go back to Auto'));
    await t.press('esc');
    await t.pump();
    expect(app.value.themePickerShown, isFalse);
    expect(t.screen.text, isNot(contains('Esc to go back to Auto')));
  });
}
