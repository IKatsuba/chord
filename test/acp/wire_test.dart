import 'dart:convert';

import 'package:chord/acp/wire.dart';
import 'package:test/test.dart';

void main() {
  List<Object?> read(List<List<int>> chunks, {int? max}) {
    final decoder = max == null
        ? LineDecoder()
        : LineDecoder(maxMessageBytes: max);
    return [
      for (final chunk in chunks)
        for (final framed in _add(decoder, chunk)) ..._shown(framed),
      for (final framed in _close(decoder)) ..._shown(framed),
    ];
  }

  List<int> b(String text) => utf8.encode(text);

  test('one message per line, blank and whitespace lines skipped', () {
    expect(read([b('{"a":1}\n\n   \n\t\n{"b":2}\n')]), [
      {'a': 1},
      {'b': 2},
    ]);
  });

  test('CRLF, a CR and LF split across chunks, and spaces around', () {
    expect(read([b('{"a":1}\r\n  {"b":2}  \r'), b('\n')]), [
      {'a': 1},
      {'b': 2},
    ]);
  });

  test('a last line without a newline is taken at the end', () {
    final decoder = LineDecoder();
    expect(_add(decoder, b('{"a":1}\n{"b"')), hasLength(1));
    expect(_add(decoder, b(':2}')), isEmpty);
    expect(_close(decoder).expand(_shown), [
      {'b': 2},
    ]);
    expect(_close(decoder), isEmpty);
  });

  test('a message split across many chunks, a character\'s bytes too', () {
    final bytes = b('{"text":"héllo ✓ 🎉"}\n');
    expect(
      read([
        for (final byte in bytes) [byte],
      ]),
      [
        {'text': 'héllo ✓ 🎉'},
      ],
    );
  });

  test('malformed UTF-8 reads as U+FFFD', () {
    expect(
      read([
        b('{"t":"a'),
        [0xFF, 0xFE],
        b('b"}\n'),
      ]),
      [
        {'t': 'a��b'},
      ],
    );
  });

  test('bad JSON is answered -32700 with id null', () {
    expect(read([b('{"a":\n')]), [
      'reply',
      {
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': -32700, 'message': 'Parse error'},
      },
    ]);
  });

  test('a batch is answered -32600 once, unread', () {
    expect(read([b('[{"jsonrpc":"2.0","id":1,"method":"x"}]\n')]), [
      'reply',
      {
        'jsonrpc': '2.0',
        'id': null,
        'error': {
          'code': -32600,
          'message': 'Invalid request: JSON-RPC batches are not supported',
        },
      },
    ]);
  });

  test('any other value is answered -32600 with it as data', () {
    for (final (line, data) in [
      ('5', 5),
      ('"x"', 'x'),
      ('true', true),
      ('null', null),
    ]) {
      expect(read([b('$line\n')]), [
        'reply',
        {
          'jsonrpc': '2.0',
          'id': null,
          'error': {'code': -32600, 'message': 'Invalid request', 'data': data},
        },
      ], reason: line);
    }
  });

  test('messages go on after a line that is not one', () {
    expect(read([b('nope\n{"a":1}\n')]), [
      'reply',
      {
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': -32700, 'message': 'Parse error'},
      },
      {'a': 1},
    ]);
  });

  group('the cap', () {
    test('a line of exactly the cap is read, its CR not counted', () {
      final line = '{"a":"${'x' * 8}"}'; // 16 bytes
      expect(read([b('$line\r\n')], max: 16), [
        {'a': 'x' * 8},
      ]);
      expect(read([b(line)], max: 16), [
        {'a': 'x' * 8},
      ]);
    });

    test('a line past it in pieces fails as soon as it passes, and nothing '
        'of it is kept', () {
      final decoder = LineDecoder(maxMessageBytes: 16);
      expect(_add(decoder, b('{"a":"xxxx')), isEmpty);
      expect(
        () => _add(decoder, b('xxxxxxx')),
        throwsA(
          isA<MessageTooLargeError>().having(
            (e) => e.toString(),
            'message',
            'Incoming ACP data exceeds the configured 16 byte limit',
          ),
        ),
      );
      expect(_add(decoder, b('{"b":2}\n')).expand(_shown), [
        {'b': 2},
      ]);
    });

    test('a whole line past it in one chunk fails too', () {
      expect(
        () => _add(LineDecoder(maxMessageBytes: 4), b('{"a":1}\n')),
        throwsA(isA<MessageTooLargeError>()),
      );
    });

    test('is the SDK\'s 32 MiB by default', () {
      expect(defaultMaxMessageBytes, 32 * 1024 * 1024);
      expect(LineDecoder().maxMessageBytes, defaultMaxMessageBytes);
      final decoder = LineDecoder();
      final mib = List.filled(1024 * 1024, 0x20);
      for (var i = 0; i < 32; i++) {
        _add(decoder, mib);
      }
      expect(() => _add(decoder, [0x20]), throwsA(isA<MessageTooLargeError>()));
    });
  });

  test('what a chunk completed before an oversized line is emitted first, '
      'in order, then the cap fails', () {
    final decoder = LineDecoder(maxMessageBytes: 8);
    final emitted = <Object?>[];
    expect(
      () => decoder.add(b('{}\nnope\n{"a":1}\n123456789'), (framed) {
        emitted.addAll(_shown(framed));
      }),
      throwsA(isA<MessageTooLargeError>()),
    );
    expect(emitted, [
      <String, Object?>{},
      'reply',
      {
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': -32700, 'message': 'Parse error'},
      },
      {'a': 1},
    ]);
  });

  test('a message goes out as one line of JSON', () {
    expect(
      utf8.decode(encodeLine({'jsonrpc': '2.0', 'method': 'x', 'params': {}})),
      '{"jsonrpc":"2.0","method":"x","params":{}}\n',
    );
    expect(
      utf8.decode(encodeLine({'t': 'line\nbreak ✓'})),
      '{"t":"line\\nbreak ✓"}\n',
    );
  });

  group('tester: framing boundaries', () {
    test('every split preserves UTF-8 and CRLF at exactly the byte cap', () {
      const message = {'t': '界👩‍💻e\u0301\u001b[31m'};
      final line = b(jsonEncode(message));
      final input = [...line, 13, 10];
      for (var split = 0; split <= input.length; split++) {
        expect(
          read([
            input.sublist(0, split),
            input.sublist(split),
          ], max: line.length),
          [message],
          reason: 'split $split',
        );
      }
      expect(
        read([
          line,
          [13],
        ], max: line.length),
        [message],
      );
    });

    test('the cap counts UTF-8 bytes and not characters', () {
      final line = b('{"t":"界"}');
      expect(line, hasLength(11));
      expect(read([line], max: 11), [
        {'t': '界'},
      ]);
      expect(() => read([line], max: 10), throwsA(isA<MessageTooLargeError>()));
    });

    test('an unfinished invalid last line emits one reply on close', () {
      final decoder = LineDecoder();
      expect(_add(decoder, b('{')), isEmpty);
      final closed = _close(decoder);
      expect(closed, hasLength(1));
      final error = (closed.single as FramingReply).reply['error'] as Map;
      expect(error['code'], -32700);
      expect(_close(decoder), isEmpty);
    });

    test('an oversized partial line retains nothing at EOF', () {
      final decoder = LineDecoder(maxMessageBytes: 4);
      expect(_add(decoder, b('1234')), isEmpty);
      expect(() => _add(decoder, b('5')), throwsA(isA<MessageTooLargeError>()));
      expect(_close(decoder), isEmpty);
    });

    test('escaped controls stay within one encoded line and decode intact', () {
      final message = <String, Object?>{
        't': '\u0000\n\r\t\u001b[31m界👩‍💻e\u0301',
      };
      final bytes = encodeLine(message);
      expect(bytes.where((byte) => byte == 10), hasLength(1));
      expect(bytes.last, 10);
      expect(read([bytes]), [message]);
    });

    test('zero room accepts blank framing but refuses an object', () {
      expect(
        read([
          [10],
          [13],
          [10],
        ], max: 0),
        isEmpty,
      );
      expect(
        () => read([b('{}\n')], max: 0),
        throwsA(isA<MessageTooLargeError>()),
      );
    });
  });
}

List<Framed> _add(LineDecoder decoder, List<int> chunk) {
  final framed = <Framed>[];
  decoder.add(chunk, framed.add);
  return framed;
}

List<Framed> _close(LineDecoder decoder) {
  final framed = <Framed>[];
  decoder.close(framed.add);
  return framed;
}

/// A message as itself; a reply as 'reply' and what it answers.
List<Object?> _shown(Framed framed) => switch (framed) {
  FramedMessage(:final message) => [message],
  FramingReply(:final reply) => ['reply', reply],
};
