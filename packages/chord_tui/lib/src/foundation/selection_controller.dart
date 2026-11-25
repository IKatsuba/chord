import 'package:meta/meta.dart';

import 'notifier.dart';
import 'selection.dart';
import 'selection_diagnostics.dart';
import 'selection_source.dart';

/// The live area endpoint behind a public selection controller.
@internal
abstract interface class SelectionClient {
  /// Current notification snapshot, without synchronization.
  SelectionValue get selectionValue;

  /// Observes current integer counts without synchronizing or resolving text.
  SelectionDiagnostics get selectionDiagnostics;

  /// Synchronizes geometry and returns a safe current copy snapshot.
  SelectionValue? selectionSnapshot();

  /// Clears current logical selection and unfinished capture.
  void clearSelection();

  /// Current exposed code containers in paint order.
  List<CodeBlockGeometry> selectionCodeBlocks();

  /// Reveals one current code container through its logical provider.
  bool revealSelectionCodeBlock(CodeBlockId id);

  /// Releases registrations and capture before controller disposal.
  void detachSelection();
}

/// Owns one area's logical range and synchronized copy/geometry queries.
class SelectionController extends ChangeNotifier {
  /// Creates an unattached controller; one live area may attach at a time.
  SelectionController();

  final Set<SelectionClient> _clients = {};
  bool _notifying = false, _again = false;

  SelectionClient? get _client {
    checkNotDisposed();
    validateAttachment();
    return _clients.firstOrNull;
  }

  /// Latest UI notification snapshot; copy actions must use [snapshot].
  SelectionValue get value =>
      _client?.selectionValue ??
      const SelectionValue(phase: SelectionPhase.none);

  /// Synchronizes before copying; null means detached or unresolved geometry.
  SelectionValue? snapshot() => _client?.selectionSnapshot();

  /// Clears endpoints and releases any unfinished gesture.
  void clear() => _client?.clearSelection();

  /// Current exposed code descriptors in paint order.
  List<CodeBlockGeometry> visibleCodeBlocks() =>
      _client?.selectionCodeBlocks() ?? const [];

  /// Current exposed geometry for [id], or null when absent/unresolved.
  CodeBlockGeometry? codeBlockGeometry(CodeBlockId id) => visibleCodeBlocks()
      .where((geometry) => geometry.block.id == id)
      .firstOrNull;

  /// Aligns a provider's code container when needed and synchronizes its view.
  bool revealCodeBlock(CodeBlockId id) =>
      _client?.revealSelectionCodeBlock(id) ?? false;

  /// Registers an area until its matching detach; checked after reconciliation.
  @internal
  void attachSelection(SelectionClient client) {
    checkNotDisposed();
    _clients.add(client);
  }

  /// Removes an area without notifying a controller already being disposed.
  @internal
  void detachSelection(SelectionClient client) => _clients.remove(client);

  /// Rejects sharing after widget reconciliation has removed old attachments.
  @internal
  void validateAttachment() {
    if (_clients.length > 1) {
      throw StateError('A SelectionController serves one live SelectionArea.');
    }
  }

  @override
  void notifyListeners() {
    if (_notifying) {
      _again = true;
      return;
    }
    _notifying = true;
    try {
      do {
        _again = false;
        super.notifyListeners();
      } while (_again && !isDisposed);
    } finally {
      _notifying = false;
    }
  }

  @override
  void dispose() {
    if (isDisposed) return;
    final clients = List.of(_clients);
    _clients.clear();
    for (final client in clients) {
      client.detachSelection();
    }
    super.dispose();
  }
}

/// Observes a controller without validating, synchronizing or retaining it.
@internal
SelectionDiagnostics selectionDiagnostics(SelectionController controller) =>
    controller._clients.firstOrNull?.selectionDiagnostics ??
    const SelectionDiagnostics();
