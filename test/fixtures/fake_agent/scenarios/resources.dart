// The ordinary MCP path draws advisory resource states supplied by the
// injected fixture reader, as the original's scenarios/resources.ts.
import '../turn.dart';
import 'chord_tools.dart';

final Map<String, Play> resources = {
  'resources': (turn) async {
    final client = await chordClient(turn);
    if (client == null) {
      await turn.say(['No chord server in this session.']);
      return 'end_turn';
    }
    try {
      await callChord(turn, client, 'get_budgets', {});
      await turn.say([
        'Resource facts are advisory; unknown data remains unknown.',
      ]);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },
};
