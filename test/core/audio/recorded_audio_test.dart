import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/audio/recorded_audio.dart';

void main() {
  group('encodePcmWav', () {
    test('encodes RIFF PCM16 mono headers and preserves every audio byte', () {
      final pcm = Uint8List.fromList(List.generate(32000, (i) => i % 256));
      final result = encodePcmWav(pcm);
      final header = ByteData.sublistView(result.bytes);
      String tag(int offset) =>
          String.fromCharCodes(result.bytes.sublist(offset, offset + 4));
      expect(tag(0), 'RIFF');
      expect(header.getUint32(4, Endian.little), result.bytes.length - 8);
      expect(tag(8), 'WAVE');
      expect(tag(12), 'fmt ');
      expect(header.getUint32(16, Endian.little), 16);
      expect(header.getUint16(20, Endian.little), 1);
      expect(header.getUint16(22, Endian.little), 1);
      expect(header.getUint32(24, Endian.little), 16000);
      expect(header.getUint32(28, Endian.little), 32000);
      expect(header.getUint16(32, Endian.little), 2);
      expect(header.getUint16(34, Endian.little), 16);
      expect(tag(36), 'data');
      expect(header.getUint32(40, Endian.little), pcm.length);
      expect(result.bytes.sublist(44), pcm);
      expect(result.durationMs, 1000);
      expect(result.mimeType, 'audio/wav');
    });
    test('encodes an empty capture as a zero-duration WAV header', () {
      final result = encodePcmWav(Uint8List(0));
      expect(result.bytes.length, 44);
      expect(result.durationMs, 0);
    });
    test('rejects an incomplete PCM16 sample', () {
      expect(() => encodePcmWav(Uint8List(3)), throwsFormatException);
    });
  });
}
