import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/haptics/haptics.dart';
import 'package:mocktail/mocktail.dart';

class _MockEngine extends Mock implements HapticEngine {}

void main() {
  group(VoiceHaptics, () {
    test('distinguishes all six voice interactions', () async {
      final engine = _MockEngine();
      when(engine.light).thenAnswer((_) async {});
      when(engine.medium).thenAnswer((_) async {});
      when(engine.heavy).thenAnswer((_) async {});
      when(engine.selection).thenAnswer((_) async {});
      final haptics = VoiceHaptics(engine);
      for (final event in VoiceHaptic.values) {
        await haptics.trigger(event);
      }
      verifyInOrder([
        engine.light,
        engine.medium,
        engine.heavy,
        engine.selection,
        engine.selection,
        engine.light,
        engine.light,
        engine.selection,
      ]);
    });
  });
}
