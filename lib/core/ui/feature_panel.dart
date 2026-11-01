import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/adaptive/adaptive_top_bar.dart';

class FeaturePanel extends StatelessWidget {
  const FeaturePanel({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppTokens.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppTokens.line),
    ),
    child: child,
  );
}

class FeaturePage extends StatelessWidget {
  const FeaturePage({
    required this.title,
    required this.child,
    this.onBack,
    super.key,
  });
  final VoidCallback? onBack;
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AdaptiveTopBar(
      title: title,
      leading: IconButton(
        tooltip: '뒤로',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed:
            onBack ??
            () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/speak');
              }
            },
      ),
    ),
    body: SafeArea(top: false, child: child),
  );
}
