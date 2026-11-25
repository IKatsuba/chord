/// The window's agents open: `window_agents.dart`'s state, with main's
/// conversation and each long-lived child's, started when it opens and
/// closed when it closes. From the original's `session/open_agents.ts`.
library;

import 'dart:async';

import '../kept.dart';
import '../notify.dart';
import 'conversation.dart';
import 'window_agents.dart' as roster;
import 'window_agents.dart' show ChildInfo, WindowAgents;

/// What an agent of the window drives: `Conversation`, or a stand-in in a
/// test.
abstract interface class Driven {
  void start();
  Future<void> close();
}

/// Every close that failed, once all of them have settled.
final class CloseFailures implements Exception {
  const CloseFailures(this.errors);

  final List<Object> errors;

  @override
  String toString() => 'Not every agent closed: ${errors.join('; ')}';
}

/// The window's agents open, their events folded into their own waits.
final class OpenAgents<C extends Driven> {
  /// [conversation] makes main's conversation for an agent, not started,
  /// reporting through `emit` under its key. [heard] takes each event an
  /// open agent reports, once its wait has taken it in, with the wait it
  /// starts. [closingHeard] takes what a closed agent still reports as it
  /// closes: what it spent then still counts.
  OpenAgents({
    required C Function(
      String agent,
      void Function(ConversationEvent event) emit,
      int key,
    )
    conversation,
    required void Function(int key, ConversationEvent event, Wait? wait) heard,
    void Function(int key, ConversationEvent event)? closingHeard,
    num Function()? now,
  }) : _make = conversation,
       _told = heard,
       _toldClosing = closingHeard,
       _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final C Function(String, void Function(ConversationEvent), int) _make;
  final void Function(int, ConversationEvent, Wait?) _told;
  final void Function(int, ConversationEvent)? _toldClosing;
  final num Function() _now;
  WindowAgents<C> _agents = roster.noAgents();

  // Closes still under way, and those that failed, which stay until
  // closeAll has reported them, so it neither stops waiting early nor says
  // every agent closed when one did not. Each is Kept: a key in the
  // window's zone or a tool call in chord's may begin it, and closeAll
  // await it from another (CTUI-114).
  final _closing = <Kept<void>>{};

  /// The roster as it stands.
  WindowAgents<C> get agents => _agents;

  /// The conversation the prompt goes to: the picked agent's.
  C? get front {
    final key = roster.shownKey(_agents);
    return key == null ? null : conversationOf(key);
  }

  /// The conversation of main or child [key]; null once it has closed.
  C? conversationOf(int key) {
    final found = roster.agentOf(_agents, key);
    return found?.child?.conversation ?? found?.main?.conversation;
  }

  /// Makes and starts main's conversation, of [agent]; once, as main's key
  /// is the window's for its life. Its key, or null on a second call.
  int? start(String agent) {
    if (_agents.main != null) return null;
    final key = _agents.nextKey;
    final conversation = _make(agent, (e) => _hear(key, e), key);
    _agents = roster.openMain(_agents, agent, conversation);
    conversation.start();
    return key;
  }

  /// Opens a long-lived child, made by [make] for its key, and starts it;
  /// the pick stays where it is. Null before main starts or with no room,
  /// and then nothing is started.
  int? openChild(
    ChildInfo info,
    C Function(void Function(ConversationEvent event) emit, int key) make,
  ) {
    if (_agents.main == null) return null;
    final key = _agents.nextKey;
    final conversation = make((e) => _hear(key, e), key);
    final opened = roster.openChild(_agents, info, conversation);
    if (opened == null) return null;
    _agents = opened.agents;
    conversation.start();
    return key;
  }

  /// Takes child [key] out at once and closes its agent; completes once
  /// the agent's process has exited.
  Future<void> closeChild(int key) {
    final child = roster.agentOf(_agents, key)?.child;
    if (child == null) return Future.value();
    _agents = roster.closeChild(_agents, key);
    return _closed(child.conversation.close());
  }

  /// Forgets the children closed, as a new or resumed session starts.
  void forgetClosed() => _agents = roster.forgetClosed(_agents);

  /// Picks agent [key].
  void pick(int key) => _agents = roster.pick(_agents, key);

  /// Moves the pick [by] rows; false when it would go above `main`, which
  /// leaves it there.
  bool movePick(int by) {
    final moved = roster.movePick(_agents, by);
    if (moved == null) return false;
    _agents = moved;
    return true;
  }

  /// A key pressed in chord: the agent shown has been looked at.
  void keyed() => _agents = roster.keyedAgents(_agents);

  /// Goes to the agent that has waited longest; false when none waits.
  bool attend() {
    final moved = roster.attend(_agents);
    if (moved == null) return false;
    _agents = moved;
    return true;
  }

  Future<void> _closed(Future<void> closing) {
    final kept = Kept(closing);
    _closing.add(kept);
    // A failed close stays until closeAll reports it.
    closing.then<void>((_) {
      _closing.remove(kept);
    }, onError: (Object _) {});
    return closing;
  }

  /// Closes main and every child at once and waits for every agent, those
  /// closed earlier included; throws [CloseFailures] with every failure
  /// once all have settled, an earlier close's too, even one that failed
  /// before this was called.
  Future<void> closeAll() async {
    final main = _agents.main;
    final children = _agents.children;
    _agents = _agents.copyWith(noMain: true, children: const []);
    if (main != null) _closed(main.conversation.close()).ignore();
    for (final child in children) {
      _closed(child.conversation.close()).ignore();
    }
    final closing = [..._closing];
    final errors = <Object>[];
    for (final each in closing) {
      try {
        await each.future;
      } on Object catch (error) {
        errors.add(error);
      }
    }
    for (final each in closing) {
      _closing.remove(each);
    }
    if (errors.isNotEmpty) throw CloseFailures(errors);
  }

  void _hear(int key, ConversationEvent event) {
    if (roster.agentOf(_agents, key) == null) {
      _toldClosing?.call(key, event);
      return;
    }
    final seen = roster.hear(_agents, key, event, _now());
    _agents = seen.agents;
    _told(key, event, seen.wait);
  }
}
