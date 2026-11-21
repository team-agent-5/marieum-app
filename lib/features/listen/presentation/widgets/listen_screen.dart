import 'package:flutter/material.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/adaptive/adaptive_top_bar.dart';

class ListenScreen extends StatelessWidget {
  const ListenScreen({
    required this.title,
    required this.closeLabel,
    required this.onClose,
    required this.children,
    super.key,
  });

  final String title;
  final String closeLabel;
  final VoidCallback onClose;
  final List<Widget> children;

  static final ButtonStyle primaryButton = FilledButton.styleFrom(
    minimumSize: const Size(0, AppTokens.buttonHeight),
    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
  );

  static final ButtonStyle secondaryButton = OutlinedButton.styleFrom(
    minimumSize: const Size(0, AppTokens.buttonHeight),
    foregroundColor: AppTokens.ink,
    backgroundColor: AppTokens.surface,
    side: const BorderSide(color: AppTokens.lineStrong),
    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTokens.buttonRadius),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTokens.bg,
    appBar: AdaptiveTopBar(
      title: title,
      leading: IconButton(
        tooltip: '뒤로',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: onClose,
      ),
    ),
    body: SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppTokens.pagePadding),
              children: children,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.pagePadding,
              8,
              AppTokens.pagePadding,
              12,
            ),
            child: OutlinedButton(
              style: secondaryButton,
              onPressed: onClose,
              child: Text(closeLabel),
            ),
          ),
        ],
      ),
    ),
  );
}

class ListenStatusMessage extends StatelessWidget {
  const ListenStatusMessage(this.message, {this.loading = false, super.key});

  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      children: [
        if (loading) ...[
          CircularProgressIndicator(
            value: MediaQuery.disableAnimationsOf(context) ? .5 : null,
          ),
          const SizedBox(height: 16),
        ],
        Text(message, style: AppTokens.title, textAlign: TextAlign.center),
      ],
    ),
  );
}
