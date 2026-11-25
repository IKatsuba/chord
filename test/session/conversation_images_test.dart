import 'package:chord/session/conversation.dart';
import 'package:chord/session/session.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

void main() {
  test("a prompt sent with images carries them as the turn's parts", () {
    fakeAsync((async) {
      final session = ScriptedSession();
      final conversation = Conversation(
        ({required onTraffic, required cancellationToken}) =>
            Future.value(session),
      )..start();
      async.flushMicrotasks();
      const parts = PromptParts(
        images: [(mimeType: 'image/png', data: 'AAAA')],
      );
      expect(
        conversation.send('see [Image #1]', null, const [], parts),
        isTrue,
      );
      async.flushMicrotasks();
      expect(session.turns.single.text, 'see [Image #1]');
      expect(session.turns.single.parts.images, parts.images);
      conversation.close();
      async.flushMicrotasks();
    });
  });
}
