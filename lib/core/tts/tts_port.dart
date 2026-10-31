import 'package:marieum_app/core/error/result.dart';

enum TtsRate { slow, normal, fast }

enum TtsVolume { soft, normal, loud }

enum VoicePlatform { ios, android }

abstract interface class TtsPort {
  Future<bool> isKoreanAvailable();
  Future<Result<void>> speak(String text);
  Future<Result<void>> stop();
}
