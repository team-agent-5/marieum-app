import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Synthesized sentences kept on the device so they replay instantly and
/// offline. Files are named by a hash of the voice and text.
class CloudTtsCache {
  CloudTtsCache({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;
  Directory? _root;

  Future<Directory> _folder() async {
    final root = _root ??= Directory('${(await _directory()).path}/tts_cache');
    if (!root.existsSync()) await root.create(recursive: true);
    return root;
  }

  /// Two 32-bit FNV-1a hashes with different seeds, as 16 hex digits.
  static String keyFor(String voice, String text) {
    String fnv(int seed) {
      var hash = seed;
      for (final unit in '$voice|$text'.codeUnits) {
        hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
      }
      return hash.toRadixString(16).padLeft(8, '0');
    }

    return fnv(0x811c9dc5) + fnv(0x050c5d1f);
  }

  Future<File?> find(String voice, String text) async {
    final folder = await _folder();
    final key = keyFor(voice, text);
    for (final extension in const ['wav', 'mp3']) {
      final file = File('${folder.path}/$key.$extension');
      if (file.existsSync() && file.lengthSync() > 0) return file;
    }
    return null;
  }

  Future<File> save(String voice, String text, Uint8List audio) async {
    final folder = await _folder();
    final riff =
        audio.length > 4 &&
        audio[0] == 0x52 &&
        audio[1] == 0x49 &&
        audio[2] == 0x46 &&
        audio[3] == 0x46;
    final file = File(
      '${folder.path}/${keyFor(voice, text)}.${riff ? 'wav' : 'mp3'}',
    );
    await file.writeAsBytes(audio, flush: true);
    return file;
  }
}
