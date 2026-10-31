import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:marieum_app/core/theme/tokens.dart';

class AdaptiveSegmentedControl<T extends Object> extends StatelessWidget {
  const AdaptiveSegmentedControl({
    required this.value,
    required this.children,
    required this.onChanged,
    this.selectedBackground,
    super.key,
  });
  final T value;
  final Map<T, Widget> children;
  final ValueChanged<T> onChanged;
  final Color? selectedBackground;
  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        backgroundColor: AppTokens.surfaceBlue,
        thumbColor: selectedBackground ?? AppTokens.surface,
        padding: const EdgeInsets.all(4),
        children: children,
        onValueChanged: (selection) {
          if (selection != null) onChanged(selection);
        },
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTokens.surfaceBlue,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTokens.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SegmentedButton<T>(
          segments: [
            for (final entry in children.entries)
              ButtonSegment(value: entry.key, label: entry.value),
          ],
          selected: {value},
          onSelectionChanged: (selection) => onChanged(selection.single),
          showSelectedIcon: false,
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
            side: const WidgetStatePropertyAll(BorderSide.none),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? selectedBackground ?? AppTokens.primarySoft
                  : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}
