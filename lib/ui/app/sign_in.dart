import 'package:chord_tui/chord_tui.dart';

import '../../session/sign_in.dart';
import '../../session/start_failure.dart' show pinLine;
import '../transcript/tools/tool.dart' show Under;

/// Under a start or a prompt the agent needs a login for: what the agent
/// says of its account, the pin chord ran, when [pinned], the ways in
/// [agent] offers, each its name bold and its description after, in the
/// agent's own words, then chord's way on.
class SignInBlock extends StatelessWidget {
  /// The block for [agent]'s [signIn].
  const SignInBlock({
    super.key,
    required this.agent,
    required this.signIn,
    this.pinned,
  });

  final String agent;
  final SignIn signIn;

  /// The `package@version` chord ran, for an agent chord pins.
  final String? pinned;

  @override
  Widget build(BuildContext context) {
    final ways = signIn.ways;
    final account = accountReported(agent, signIn.account);
    final plain = account == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (account != null) Under(first: true, child: Text(account)),
        if (pinned case final pinned?)
          Under(first: plain, child: Text(pinLine(pinned))),
        if (ways.isNotEmpty)
          Under(
            first: plain && pinned == null,
            child: Text(offersLine(agent, ways.length)),
          ),
        for (final way in ways)
          Under(
            first: false,
            // Indented under the text, a wrapped description hangs there.
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text.rich(
                TextSpan(
                  '',
                  children: [
                    if (way.name case final name?)
                      TextSpan(
                        '',
                        style: Style.bold,
                        children: [parseAnsi(name)],
                      ),
                    if (way.name != null && way.description != null)
                      const TextSpan(' · '),
                    if (way.description case final description?)
                      parseAnsi(description),
                  ],
                ),
              ),
            ),
          ),
        Under(
          first: plain && pinned == null && ways.isEmpty,
          child: Text(wayOn(agent)),
        ),
      ],
    );
  }
}
