import 'package:flutter/foundation.dart';

/// Development log for the main flows. Silent in release builds; never pass
/// tokens or passwords.
abstract final class AppLog {
  static bool enabled = !kReleaseMode;

  static void net(String message) => _write('net', message);
  static void speak(String message) => _write('speak', message);
  static void tts(String message) => _write('tts', message);
  static void ws(String message) => _write('ws', message);

  static void _write(String tag, String message) {
    if (!enabled) return;
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    // A broken character in the output made `flutter run` drop the log.
    debugPrint('[$time][$tag] ${message.replaceAll('\uFFFD', '?')}');
  }
}
