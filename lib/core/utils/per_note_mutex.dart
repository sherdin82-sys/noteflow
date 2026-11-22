import 'dart:async';

/// An asynchronous mutex that serializes concurrent operations targeting the same note ID.
/// Supports FIFO queued execution, reliable release in `finally`, exception safety,
/// and automatic lock cleanup to avoid memory leaks.
class PerNoteMutex {
  final Map<String, Future<void>> _locks = {};

  /// Executes [action] after any previously scheduled actions for [noteId] have completed.
  /// Guarantees that the lock is released in a `finally` block even if [action] throws.
  /// Removes the key from the lock map when the queue is drained.
  Future<T> runLocked<T>(String noteId, Future<T> Function() action) async {
    final previousLock = _locks[noteId];
    final completer = Completer<void>();
    _locks[noteId] = completer.future;

    if (previousLock != null) {
      try {
        await previousLock;
      } catch (_) {
        // Preceding task errors should not block queued actions
      }
    }

    try {
      return await action();
    } finally {
      // Clean up lock if no further operations are queued behind this one
      if (identical(_locks[noteId], completer.future)) {
        _locks.remove(noteId);
      }
      completer.complete();
    }
  }

  /// Returns true if an operation is currently executing or queued for [noteId].
  bool isLocked(String noteId) => _locks.containsKey(noteId);

  /// Returns the current count of active note locks.
  int get activeLockCount => _locks.length;
}
