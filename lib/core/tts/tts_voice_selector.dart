import 'package:marieum_app/core/tts/tts_voice.dart';

abstract interface class TtsVoiceSelector {
  Future<List<TtsVoice>> availableVoices();
  TtsVoice? get currentVoice;
  Future<void> selectVoice(String? id);
}
