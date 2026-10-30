import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/core/ui/adaptive/adaptive_top_bar.dart';

/// Route scaffolding; feature content is supplied by later tasks.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AdaptiveTopBar(
        title: title,
        leading: IconButton(
          tooltip: '뒤로',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/speak');
            }
          },
        ),
      ),
      body: const SizedBox.expand(),
    );
  }
}
