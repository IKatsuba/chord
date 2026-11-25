import 'package:chord/shell_quote.dart';
import 'package:test/test.dart';

void main() {
  test('each word quotes as shell-quote 1.12.0 quotes it', () {
    // Pairs printed by the original's shell-quote on the same words.
    const pairs = {
      'plain': 'plain',
      'a b': "'a b'",
      "it's": '"it\'s"',
      '': "''",
      r'$HOME': r'\$HOME',
      'x"y': '\'x"y\'',
      '--acp': '--acp',
      "it's!": '\'it\'"\'"\'s!\'',
      r'a\b': r"'a\b'",
      'C:foo': r'C\:foo',
      'a*b': r'a\*b',
      'é ü': "'é ü'",
      'tab\there': "'tab\there'",
      '`cmd`': r'\`cmd\`',
      r'a$b c': r"'a$b c'",
      '~/x': r'\~/x',
      'k=v': r'k\=v',
    };
    for (final MapEntry(:key, :value) in pairs.entries) {
      expect(quote([key]), value, reason: key);
    }
  });

  test('words join with one space', () {
    expect(quote(['my-agent', '--acp', '']), "my-agent --acp ''");
    expect(quote([]), '');
  });
}
