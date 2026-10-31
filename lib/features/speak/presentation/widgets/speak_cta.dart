import 'package:flutter/material.dart';
import 'package:marieum_app/core/theme/tokens.dart';

class SpeakCta extends StatelessWidget {
  const SpeakCta({required this.onLongPress, super.key});
  final VoidCallback onLongPress;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        button: true,
        label: '길게 눌러 녹음',
        onTap: onLongPress,
        child: GestureDetector(
          key: const ValueKey('speak_cta'),
          onLongPress: onLongPress,
          child: SizedBox(
            width: 248,
            height: 248,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (final size in [248.0, 216.0])
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTokens.primary.withValues(alpha: .22),
                        width: 1.5,
                      ),
                    ),
                  ),
                Container(
                  width: 184,
                  height: 184,
                  decoration: BoxDecoration(
                    color: AppTokens.primaryStrong,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTokens.primary, width: 9),
                  ),
                  child: const ExcludeSemantics(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.mic_rounded,
                          color: AppTokens.surface,
                          size: 34,
                        ),
                        SizedBox(height: 4),
                        Text(
                          '말하기',
                          style: TextStyle(
                            fontSize: 29,
                            fontWeight: FontWeight.w900,
                            color: AppTokens.surface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        '길게 누르고 말씀하세요',
        style: TextStyle(fontSize: 13, color: AppTokens.ink2),
      ),
    ],
  );
}
