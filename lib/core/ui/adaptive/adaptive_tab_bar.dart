import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:marieum_app/core/theme/tokens.dart';

class AdaptiveTabBar extends StatelessWidget {
  const AdaptiveTabBar({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SafeArea(
        top: false,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.tabRadius),
          child: isIOS
              ? CupertinoTabBar(
                  border: null,
                  currentIndex: selectedIndex,
                  onTap: onSelected,
                  height: AppTokens.tabHeight,
                  backgroundColor: AppTokens.surface.withValues(alpha: 0.78),
                  activeColor: AppTokens.primaryStrong,
                  inactiveColor: AppTokens.ink2,
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.mic),
                      label: '말하기',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.list_bullet),
                      label: '요청',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.settings),
                      label: '설정',
                    ),
                  ],
                )
              : NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelected,
                  height: AppTokens.tabHeight,
                  backgroundColor: AppTokens.surface,
                  indicatorColor: AppTokens.primarySoft,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.mic_none_rounded),
                      label: '말하기',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.list_alt_rounded),
                      label: '요청',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      label: '설정',
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
