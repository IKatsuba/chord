/// A function with no arguments and no result: a listener, a callback.
typedef VoidCallback = void Function();

/// Something that tells its listeners when it changes.
abstract class Listenable {
  /// For subclasses.
  const Listenable();

  /// Calls [listener] on every change, until it is removed.
  void addListener(VoidCallback listener);

  /// Stops calling [listener].
  void removeListener(VoidCallback listener);
}

/// A [Listenable] that calls its listeners when told to.
class ChangeNotifier implements Listenable {
  /// A notifier with no listeners yet.
  ChangeNotifier();

  final List<VoidCallback> _listeners = [];
  bool _disposed = false;

  /// Whether anyone listens.
  bool get hasListeners => _listeners.isNotEmpty;

  /// Whether [dispose] was called; a disposed notifier takes no listeners
  /// and notifies nobody.
  bool get isDisposed => _disposed;

  /// Throws when this notifier is disposed.
  void checkNotDisposed() {
    if (_disposed) throw StateError('$runtimeType was used after dispose.');
  }

  @override
  void addListener(VoidCallback listener) {
    checkNotDisposed();
    _listeners.add(listener);
  }

  // Allowed after dispose: a widget unmounted later still lets go of it.
  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// Calls every listener, in the order they were added.
  void notifyListeners() {
    checkNotDisposed();
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  /// Lets go of every listener; the notifier takes no more.
  void dispose() {
    _disposed = true;
    _listeners.clear();
  }
}

/// A [ChangeNotifier] holding one value, notifying when it changes.
class ValueNotifier<T> extends ChangeNotifier {
  /// A notifier starting at the given value.
  ValueNotifier(this._value);

  T _value;

  /// The value held; setting a different one notifies the listeners.
  T get value => _value;
  set value(T v) {
    if (v == _value) return;
    _value = v;
    notifyListeners();
  }
}
