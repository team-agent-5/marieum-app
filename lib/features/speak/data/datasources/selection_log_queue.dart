import 'dart:async';
import 'dart:convert';

import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/core/storage/sequence_store.dart';

/// Persists `/phrase/selection` payloads until the server accepts them.
/// Transient failures keep the item for a later flush; payloads the server
/// rejects as invalid are dropped so they cannot block the queue.
class SelectionLogQueue {
  SelectionLogQueue({
    required this._prefs,
    required this._sequence,
    required this._send,
  });

  static const maxItems = 50;

  final PrefsStore _prefs;
  final SequenceStore _sequence;
  final Future<Result<String>> Function(Map<String, Object?> body) _send;
  Future<void> _tail = Future.value();

  List<Map<String, Object?>> get pending {
    try {
      final raw = _prefs.readString(PrefsKeys.pendingSelectionLogs);
      if (raw == null) return const [];
      return [
        for (final item in jsonDecode(raw) as List<Object?>)
          Map<String, Object?>.from(item! as Map),
      ];
    } on Object {
      return const [];
    }
  }

  Future<void> enqueue(Map<String, Object?> body) => _serialize(() async {
    final items = [...pending, body];
    await _save(items.skip(items.length - maxItems.clamp(0, items.length)));
    await _drain();
  });

  Future<void> flush() => _serialize(_drain);

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _tail.then((_) => operation()).catchError((Object _) {});
    _tail = next;
    return next;
  }

  Future<void> _drain() async {
    var items = pending;
    while (items.isNotEmpty) {
      final body = items.first;
      final result = await _send(body);
      if (result case FailureResult(:final failure) when _retryable(failure)) {
        return;
      }
      if (result case Success(:final value) when body['action'] == 'selected') {
        await _sequence.save(value);
      }
      items = items.sublist(1);
      await _save(items);
    }
  }

  static bool _retryable(Failure failure) => switch (failure) {
    NetworkFailure() || TimeoutFailure() || UnauthorizedFailure() => true,
    ServerFailure(:final statusCode) => statusCode == null || statusCode >= 500,
    _ => false,
  };

  Future<void> _save(Iterable<Map<String, Object?>> items) =>
      _prefs.writeString(
        PrefsKeys.pendingSelectionLogs,
        jsonEncode(items.toList(growable: false)),
      );
}
