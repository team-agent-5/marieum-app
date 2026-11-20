import 'dart:io';
import 'dart:typed_data';

import 'package:marieum_app/core/audio/recorded_audio.dart';
import 'package:marieum_app/core/log/app_log.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps what the live microphone heard and what was sent for it, as two
/// WAV files of the same length, to tell by ear whether the processing or
/// the recognizer loses the words. Turned on with
/// `--dart-define=LIVE_AUDIO_DUMP=true`; the files go to the app's cache
/// folder under `live_audio`.
class LiveAudioDump {
  LiveAudioDump({Future<Directory> Function()? directory})
    : _directory = directory ?? getTemporaryDirectory;

  static const enabled = bool.fromEnvironment('LIVE_AUDIO_DUMP');

  /// Ten minutes of PCM16 16 kHz mono per file at most.
  static const int _maxBytes = 10 * 60 * 32000;

  final Future<Directory> Function() _directory;
  final _mic = BytesBuilder(copy: false);
  final _sent = BytesBuilder(copy: false);

  /// Seconds kept so far, to find a logged moment in the files.
  double get seconds => _mic.length / 32000;

  void add(Uint8List mic, Uint8List sent) {
    if (_mic.length >= _maxBytes) return;
    _mic.add(mic);
    _sent.add(sent);
  }

  Future<void> save() async {
    if (_mic.isEmpty) return;
    try {
      final folder = Directory('${(await _directory()).path}/live_audio');
      await folder.create(recursive: true);
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final base = '${folder.path}/$stamp';
      await File('${base}_mic.wav').writeAsBytes(
        encodePcmWav(_mic.takeBytes()).bytes,
      );
      await File('${base}_sent.wav').writeAsBytes(
        encodePcmWav(_sent.takeBytes()).bytes,
      );
      AppLog.speak('live audio kept in ${base}_mic.wav and ${base}_sent.wav');
    } on Object catch (error) {
      AppLog.speak('live audio not kept ${error.runtimeType}');
    }
  }
}
