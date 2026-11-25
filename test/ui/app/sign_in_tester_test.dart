import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/sign_in.dart';
import 'package:chord/ui/app/sign_in.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester: sign-in block method layout', () {
    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets(
        'only names are bold and long descriptions hang at their column $size',
        (t) async {
          final description =
              'Description begins ${'long words and 日本語 ' * 8}description ends.';
          final signIn = SignIn(
            'Authentication required',
            waysOf([
              acp.AuthMethod.fromJson({
                'id': 'empty',
                'name': ' ',
                'description': ' ',
              }),
              acp.AuthMethod.fromJson({
                'id': 'description',
                'name': '',
                'description': 'Description only',
              }),
              acp.AuthMethod.fromJson({
                'id': 'long',
                'name': '\x1b[31mMethod 界👩‍💻e\u0301\x1b[39m',
                'description': description,
              }),
              acp.AuthMethod.fromJson({'id': 'named', 'name': 'Name only'}),
            ]),
          );
          await t.pumpWidget(
            SignInBlock(agent: 'fake', signIn: signIn),
            size: size,
          );
          final lines = t.screen.lines;
          final at = lines.indexWhere((row) => row.contains('Method'));
          final column = lines[at].indexOf('Method');
          expect(signIn.ways, hasLength(3));
          expect(lines.first, '  ⎿  fake offers these sign-ins:');
          expect(
            lines
                .firstWhere((row) => row.contains('Description only'))
                .indexOf('Description'),
            column,
          );
          final tail = lines.firstWhere((row) => row.contains('ends.'));
          expect(tail.indexOf(tail.trimLeft()), column);
          expect(t.screen.styleAt(column, at).isBold, isTrue);
          expect(t.screen.styleAt(column, at).fg, Colors.red);
          expect(t.screen.styleAt(column, 1).isBold, isFalse);
          final body = lines[at].indexOf('Description');
          expect(t.screen.styleAt(body, at).isBold, isFalse);
          final before = t.screen.buffer.lines;
          await t.resize(Size.zero);
          await t.resize(const Size(1, 1));
          await t.resize(size);
          expect(t.screen.buffer.lines, before);
        },
      );
    }

    testWidgets('filtered blank ways show guidance without a heading', (
      t,
    ) async {
      await t.pumpWidget(
        SignInBlock(
          agent: 'fake',
          signIn: SignIn(
            'Authentication required',
            waysOf([
              acp.AuthMethod.fromJson({
                'id': 'empty',
                'name': ' ',
                'description': ' ',
              }),
            ]),
          ),
        ),
      );
      expect(t.screen.text, isNot(contains('fake offers')));
      expect(
        t.screen.lines.first,
        startsWith('  ⎿  chord does not sign agents in.'),
      );
    });

    testWidgets('a thousand replacements remove obsolete ways', (t) async {
      final methods = ValueNotifier(
        const SignIn('old', [(name: 'obsolete', description: null)]),
      );
      addTearDown(methods.dispose);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: methods,
          builder: (_) => SignInBlock(agent: 'fake', signIn: methods.value),
        ),
      );
      for (var i = 0; i < 1000; i++) {
        methods.value = SignIn('current', [
          (name: 'Method $i', description: null),
        ]);
      }
      await t.pump();
      expect(t.screen, shows('Method 999'));
      expect(t.screen.text, isNot(contains('obsolete')));
      methods.value = const SignIn('none', []);
      await t.pump();
      expect(t.screen.text, isNot(contains('fake offers')));
      expect(t.screen.text, isNot(contains('Method')));
      await t.pumpWidget(const SizedBox());
      methods.value = const SignIn('late', [
        (name: 'late method', description: null),
      ]);
      await t.pump();
      expect(t.screen.text, isEmpty);
    });
  });
}
