import 'dart:async';

class SessionExpirySignal {
  final _controller = StreamController<void>.broadcast(sync: true);
  Stream<void> get expired => _controller.stream;
  void emit() {
    if (!_controller.isClosed) _controller.add(null);
  }

  Future<void> dispose() => _controller.close();
}
