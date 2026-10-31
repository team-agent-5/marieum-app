import 'package:flutter/services.dart';

enum VoiceHaptic {
  recordingStarted,
  recordingStopped,
  recordingLimit,
  selected,
  playbackStarted,
  playbackStopped,
}

abstract interface class HapticEngine {
  Future<void> light();
  Future<void> medium();
  Future<void> heavy();
  Future<void> selection();
}

class PlatformHapticEngine implements HapticEngine {
  @override
  Future<void> light() => HapticFeedback.lightImpact();
  @override
  Future<void> medium() => HapticFeedback.mediumImpact();
  @override
  Future<void> heavy() => HapticFeedback.heavyImpact();
  @override
  Future<void> selection() => HapticFeedback.selectionClick();
}

class VoiceHaptics {
  VoiceHaptics(this._engine);
  final HapticEngine _engine;
  Future<void> trigger(VoiceHaptic event) async {
    switch (event) {
      case VoiceHaptic.recordingStarted:
        await _engine.light();
      case VoiceHaptic.recordingStopped:
        await _engine.medium();
      case VoiceHaptic.recordingLimit:
        await _engine.heavy();
      case VoiceHaptic.selected:
        await _engine.selection();
      case VoiceHaptic.playbackStarted:
        await _engine.selection();
        await Future<void>.delayed(const Duration(milliseconds: 70));
        await _engine.light();
      case VoiceHaptic.playbackStopped:
        await _engine.light();
        await Future<void>.delayed(const Duration(milliseconds: 70));
        await _engine.selection();
    }
  }
}
