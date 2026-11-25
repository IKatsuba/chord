// What a session is opened with on the original's fake agent: what chord
// declares toward it, the client's MCP servers by the transports it takes,
// and a client's initial config options.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/acp/connection.dart'
    show openHeadlessAgent, openWindowAgent;
import 'package:chord/acp/schema.dart';
import 'package:chord/acp/traffic.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/upstream.dart';
import 'package:test/test.dart';

import 'session_fake.dart';

bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

const _stdio = {
  'name': 'files',
  'command': 'files-mcp',
  'args': <Object?>[],
  'env': <Object?>[],
};
const _http = {
  'type': 'http',
  'name': 'docs',
  'url': 'https://docs',
  'headers': <Object?>[],
};

/// Opens a session on the fake with [flags] through [open], hands it and
/// its traffic to [body], then closes it.
Future<void> _with(
  Future<void> Function(Session session, TrafficRecorder traffic) body, {
  List<String> flags = const [],
  SessionOpener? open,
  List<Map<String, Object?>> mcpServers = const [],
  bool noMcpServers = false,
  List<Map<String, Object?>> entries = const [],
}) async {
  final dir = Directory.systemTemp.createTempSync('chord-options-');
  final traffic = TrafficRecorder();
  final session = await openSession(
    agent: 'fake',
    command: fakeAgentCommand(null, flags),
    cwd: dir.path,
    open: open ?? fakeSessionOpener(),
    onTraffic: traffic.add,
    mcpServers: mcpServers,
    noMcpServers: noMcpServers,
    entries: entries,
  );
  try {
    await body(session, traffic);
  } finally {
    await session.close();
    dir.deleteSync(recursive: true);
  }
}

Map<String, Object?> _sent(TrafficRecorder traffic, String method) => traffic
    .heard
    .whereType<ChordTraffic>()
    .map((traffic) => traffic.message)
    .lastWhere((message) => message['method'] == method);

void main() {
  final skip = fakeAgentSkip;

  test(
    '-p and the window declare forms, plans by id, subagents, compactions, '
    'notices and terminal output; '
    'chord acp its set, notices only for a client that declared them',
    () async {
      await _with((session, traffic) async {
        expect(
          (_sent(traffic, 'initialize')['params'] as Map)['clientCapabilities'],
          {
            'elicitation': {
              'form': <String, Object?>{},
              'url': <String, Object?>{},
            },
            'plan': <String, Object?>{},
            'session': {
              'compaction': <String, Object?>{},
              'notices': <String, Object?>{},
            },
            'subagents': <String, Object?>{},
            '_meta': {'terminal_output_delta': true},
          },
        );
      }, open: openHeadlessAgent);
      await _with((session, traffic) async {
        expect(
          (_sent(traffic, 'initialize')['params'] as Map)['clientCapabilities'],
          {
            'elicitation': {
              'form': <String, Object?>{},
              'url': <String, Object?>{},
            },
            'plan': <String, Object?>{},
            'session': {
              'compaction': <String, Object?>{},
              'notices': <String, Object?>{},
            },
            'subagents': <String, Object?>{},
            '_meta': {'terminal_output_delta': true},
          },
        );
      }, open: openWindowAgent);
      // Written out, not computed, so a wrong declaration cannot pass on
      // both sides.
      const declared = {
        true: {
          'elicitation': {
            'form': <String, Object?>{},
            'url': <String, Object?>{},
          },
          'plan': <String, Object?>{},
          'session': {
            'compaction': <String, Object?>{},
            'notices': <String, Object?>{},
          },
          'subagents': <String, Object?>{},
          '_meta': {'terminal_output_delta': true},
        },
        false: {
          'elicitation': {
            'form': <String, Object?>{},
            'url': <String, Object?>{},
          },
          'plan': <String, Object?>{},
          'session': {'compaction': <String, Object?>{}},
          'subagents': <String, Object?>{},
          '_meta': {'terminal_output_delta': true},
        },
      };
      for (final notices in [true, false]) {
        await _with(
          (session, traffic) async {
            expect(
              (_sent(traffic, 'initialize')['params']
                  as Map)['clientCapabilities'],
              declared[notices],
            );
          },
          open: fakeOpenerWith(
            capabilities: ClientCapabilities.fromJson(
              acpCapabilities(notices: notices),
            ),
          ),
        );
      }
    },
    skip: skip,
  );

  test(
    'a stdio-only agent is given the stdio servers, the rest held back',
    () async {
      await _with(
        (session, traffic) async {
          expect(
            (_sent(traffic, 'session/new')['params'] as Map)['mcpServers'],
            [_stdio],
          );
          expect(
            [for (final held in session.heldBack) held.toJson()],
            [
              {
                'server': 'docs',
                'agent': 'fake',
                'transport': 'http',
                'takes': ['stdio'],
              },
            ],
          );
        },
        flags: ['--mcp-transports', 'none'],
        mcpServers: [_http, _stdio],
      );
    },
    skip: skip,
  );

  test(
    'an HTTP and SSE agent is given both, and --no-mcp-servers none',
    () async {
      await _with((session, traffic) async {
        expect((_sent(traffic, 'session/new')['params'] as Map)['mcpServers'], [
          _http,
          _stdio,
        ]);
        expect(session.heldBack, isEmpty);
      }, mcpServers: [_http, _stdio]);
      await _with(
        (session, traffic) async {
          expect(
            (_sent(traffic, 'session/new')['params'] as Map)['mcpServers'],
            isEmpty,
          );
          expect(session.heldBack.map((held) => held.from), [
            '--no-mcp-servers',
            '--no-mcp-servers',
          ]);
        },
        mcpServers: [_http, _stdio],
        noMcpServers: true,
      );
    },
    skip: skip,
  );

  test('an agent that takes options gets a client\'s entries with '
      'session/new', () async {
    final entries = [
      {'configId': 'effort', 'value': 'high'},
    ];
    await _with(
      (session, traffic) async {
        expect(
          (_sent(traffic, 'session/new')['params'] as Map)['configOptions'],
          entries,
        );
        final effort = session.state.configOptions.firstWhere(
          (option) => option['id'] == 'effort',
        );
        expect(effort['currentValue'], 'high');
      },
      flags: ['--options', 'apply'],
      entries: entries,
    );
  }, skip: skip);

  test('an entry the agent refuses after the session is up fails the start, '
      'and closing stops the agent', () async {
    final dir = Directory.systemTemp.createTempSync('chord-options-');
    final pids = <int>[];
    final failed = Completer<ConnectFailed>();
    final conversation = Conversation(
      ({required onTraffic, required cancellationToken}) => openSession(
        agent: 'fake',
        command: fakeAgentCommand(null, ['--refuse-config']),
        cwd: dir.path,
        open: fakeSessionOpener(pids.add),
        onTraffic: onTraffic,
        cancellationToken: cancellationToken,
      ),
      starting: const Starting(
        entries: [
          {'configId': 'effort', 'value': 'high'},
        ],
      ),
    );
    conversation.listen((event) {
      if (event is ConnectFailed && !failed.isCompleted) failed.complete(event);
    });
    conversation.start();
    final event = await failed.future.timeout(const Duration(seconds: 20));
    expect(
      event.message,
      startsWith('Could not start with effort high, set by the client: '),
    );
    await conversation.close();
    expect(pids.where(_alive), isEmpty);
    dir.deleteSync(recursive: true);
  }, skip: skip);

  group('tester U8 reopened MCP filtering', () {
    for (final resume in [false, true]) {
      for (final none in [false, true]) {
        test(
          '${resume ? 'resume' : 'load'} filters client servers with noMcp=$none',
          () async {
            final dir = Directory.systemTemp.createTempSync(
              'chord-options-reopen-',
            );
            final pids = <int>[];
            Session? session;
            try {
              final traffic = TrafficRecorder();
              session = await openSession(
                agent: 'fake',
                command: fakeAgentCommand(null, [
                  '--mcp-transports',
                  'none',
                  if (resume) ...['--resume-only', '--no-load'],
                ]),
                cwd: dir.path,
                resume: Resume(
                  sessionId: '11111111-1111-4111-8111-111111111111',
                  cwd: dir.path,
                ),
                open: fakeSessionOpener(pids.add),
                onTraffic: traffic.add,
                mcpServers: [_http, _stdio],
                noMcpServers: none,
              );
              final method = resume ? 'session/resume' : 'session/load';
              expect(
                (_sent(traffic, method)['params'] as Map)['mcpServers'],
                none ? [] : [_stdio],
              );
              expect(
                session.heldBack.map((h) => h.server),
                none ? ['docs', 'files'] : ['docs'],
              );
              expect(
                session.heldBack.map((h) => h.from),
                none ? ['--no-mcp-servers', '--no-mcp-servers'] : [null],
              );
            } finally {
              await session?.close();
              expect(pids.where(_alive), isEmpty);
              dir.deleteSync(recursive: true);
            }
          },
          skip: skip,
        );
      }
    }
  });
}
