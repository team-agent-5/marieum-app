import 'dart:typed_data';

class RecordedAudio {
  const RecordedAudio({required this.bytes, required this.durationMs});
  final Uint8List bytes;
  final int durationMs;
  String get mimeType => 'audio/wav';
}

RecordedAudio encodePcmWav(Uint8List pcm) {
  if (pcm.length.isOdd) {
    throw const FormatException('PCM16 requires whole samples.');
  }
  final bytes = Uint8List(44 + pcm.length);
  final header = ByteData.sublistView(bytes);
  void tag(int offset, String value) =>
      bytes.setRange(offset, offset + 4, value.codeUnits);
  tag(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 16000, Endian.little)
    ..setUint32(28, 32000, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  tag(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  bytes.setRange(44, bytes.length, pcm);
  return RecordedAudio(bytes: bytes, durationMs: pcm.length * 1000 ~/ 32000);
}
