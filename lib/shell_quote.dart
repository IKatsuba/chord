// What a command given as words looks like typed into a shell, as the
// original shows it: its quote() comes from shell-quote, which no Dart
// package reproduces (docs/decisions.md, "CTUI-29: quote command words as
// shell-quote does").
//
// The string branch of quote() follows shell-quote 1.12.0; its operator,
// glob and comment tokens have no use here.
// https://github.com/ljharb/shell-quote/blob/v1.12.0/quote.js
//
// The MIT License
//
// Copyright (c) 2013 James Halliday (mail@substack.net)
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.

final _quoteOrSpace = RegExp(r'["\s\\]');
final _quoteOrSpaceOrApostrophe = RegExp(r'''["'\s]''');
final _special = RegExp(r'''([A-Za-z]:)?([#!"$&'()*,:;<=>?@[\\\]^`{|}~])''');
final _doubleQuoted = RegExp(r'(["\\$`])');

/// [words] as one line a shell reads back as the same words.
String quote(List<String> words) => words.map(_word).join(' ');

String _word(String s) {
  if (s.isEmpty) return "''";
  if (s.contains("'") && s.contains('!')) {
    return "'${s.replaceAll("'", '\'"\'"\'')}'";
  }
  if (_quoteOrSpace.hasMatch(s) && !s.contains("'")) return "'$s'";
  if (_quoteOrSpaceOrApostrophe.hasMatch(s)) {
    return '"${s.replaceAllMapped(_doubleQuoted, (m) => '\\${m[1]}')}"';
  }
  return s.replaceAllMapped(_special, (m) => '${m[1] ?? ''}\\${m[2]}');
}
