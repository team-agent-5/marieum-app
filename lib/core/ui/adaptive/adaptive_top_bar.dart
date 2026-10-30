import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:marieum_app/core/theme/tokens.dart';

class AdaptiveTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AdaptiveTopBar({
    required this.title,
    this.leading,
    this.large = false,
    super.key,
  });

  final String title;
  final Widget? leading;
  final bool large;

  @override
  Size get preferredSize => Size.fromHeight(large ? 72 : 60);

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform != TargetPlatform.iOS) {
      return AppBar(title: Text(title), leading: leading);
    }
    if (!large) {
      return CupertinoNavigationBar(
        middle: Text(title),
        leading: leading,
        automaticallyImplyLeading: false,
        backgroundColor: AppTokens.bg.withValues(alpha: 0.82),
      );
    }
    return ColoredBox(
      color: AppTokens.bg.withValues(alpha: 0.82),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ?leading,
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 30,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.75,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
