import 'package:chord/acp/traffic.dart';
import 'package:test/test.dart';

void main() {
  test('each crossing reaches the subscriber, in order, as it came', () {
    final heard = <Traffic>[];
    final tap = TrafficTap(heard.add);
    final sent = {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'};
    final answered = {'jsonrpc': '2.0', 'id': 1, 'result': {}};
    tap.hear(Traffic.chord(sent));
    tap.hear(const Traffic.stderr('starting\n'));
    tap.hear(Traffic.agent(answered));
    expect(heard, hasLength(3));
    expect(identical((heard[0] as ChordTraffic).message, sent), isTrue);
    expect((heard[1] as StderrTraffic).text, 'starting\n');
    expect(identical((heard[2] as AgentTraffic).message, answered), isTrue);
  });

  test('a subscriber that throws is caught, and the next crossing still '
      'reaches it', () {
    final heard = <Traffic>[];
    final tap = TrafficTap((traffic) {
      heard.add(traffic);
      if (heard.length == 1) throw StateError('a reducer bug');
    });
    expect(() => tap.hear(const Traffic.stderr('a')), returnsNormally);
    tap.hear(const Traffic.stderr('b'));
    expect([for (final t in heard) (t as StderrTraffic).text], ['a', 'b']);
  });

  test('the three kinds dispatch by pattern', () {
    String kind(Traffic traffic) => switch (traffic) {
      AgentTraffic() => 'agent',
      ChordTraffic() => 'chord',
      StderrTraffic() => 'stderr',
    };
    expect(
      [
        kind(const Traffic.agent({})),
        kind(const Traffic.chord({})),
        kind(const Traffic.stderr('')),
      ],
      ['agent', 'chord', 'stderr'],
    );
  });

  group('tester: traffic continuity', () {
    test(
      'a thousand crossings retain order despite repeated subscriber failures',
      () {
        final heard = <Traffic>[];
        final tap = TrafficTap((traffic) {
          heard.add(traffic);
          if (heard.length % 7 == 0) throw 'subscriber failure';
        });
        final sent = <Traffic>[
          for (var i = 0; i < 1000; i++)
            switch (i % 3) {
              0 => Traffic.agent({
                'id': i,
                'future': [null, true],
              }),
              1 => Traffic.chord({'id': i}),
              _ => Traffic.stderr('界👩‍💻e\u0301\u001b[31m$i'),
            },
        ];
        for (final traffic in sent) {
          tap.hear(traffic);
        }
        expect(heard, orderedEquals(sent));
        for (var i = 0; i < sent.length; i++) {
          expect(heard[i], same(sent[i]));
        }
      },
    );
  });
}
