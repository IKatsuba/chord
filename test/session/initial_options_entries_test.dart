import 'package:chord/acp/schema.dart';
import 'package:chord/session/initial_options.dart';
import 'package:test/test.dart';

InitializeResponse _init({String? name, Object? options}) =>
    InitializeResponse.fromJson({
      'protocolVersion': 1,
      'agentCapabilities': {
        'sessionCapabilities': {'options': ?options},
      },
      if (name != null) 'agentInfo': {'name': name, 'version': '1'},
    });

const _none = (model: null, effort: null, mode: null);
const _claude = '@agentclientprotocol/claude-agent-acp';

void main() {
  test('an agent the table does not know gets a client\'s entries unchanged '
      'where it takes options', () {
    final entries = [
      {'configId': 'effort', 'value': 'high'},
      {'type': 'boolean', 'configId': 'fast', 'value': true},
    ];
    expect(
      initialEntries(_init(name: 'other', options: <String, Object?>{}), (
        model: 'big',
        effort: null,
        mode: null,
      ), entries: entries),
      entries,
    );
  });

  test('an agent that takes no options gets none, the client\'s included', () {
    expect(
      initialEntries(
        _init(name: _claude),
        _none,
        entries: [
          {'configId': 'effort', 'value': 'high'},
        ],
      ),
      isEmpty,
    );
  });

  test('a client\'s entry takes the place of chord\'s for the same id, after '
      'chord\'s others', () {
    expect(
      initialEntries(
        _init(name: _claude, options: <String, Object?>{}),
        (model: 'big', effort: 'low', mode: 'plan'),
        entries: [
          {'configId': 'mode', 'value': 'default'},
        ],
      ),
      [
        {'configId': 'model', 'value': 'big'},
        {'configId': 'effort', 'value': 'low'},
        {'configId': 'mode', 'value': 'default'},
      ],
    );
  });
}
