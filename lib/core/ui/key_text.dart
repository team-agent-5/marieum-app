import 'package:flutter/material.dart';

class KeyText extends StatelessWidget {
  const KeyText(
    this.text, {
    this.style,
    this.textAlign,
    this.maxLines,
    super.key,
  });
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
    textScaler: KeyTextScaler(
      MediaQuery.textScalerOf(context),
      LargeTextScope.enabledOf(context) ? 1.25 : 1,
    ),
  );
}

class KeyTextScaler extends TextScaler {
  const KeyTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;
  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
}

class LargeTextScope extends InheritedWidget {
  const LargeTextScope({
    required this.enabled,
    required super.child,
    super.key,
  });
  final bool enabled;
  static bool enabledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LargeTextScope>()?.enabled ??
      false;
  @override
  bool updateShouldNotify(LargeTextScope oldWidget) =>
      enabled != oldWidget.enabled;
}
