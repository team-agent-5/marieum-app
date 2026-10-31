import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/navigation/app_drawer.dart';
import 'package:marieum_app/core/ui/adaptive/adaptive_tab_bar.dart';
import 'package:marieum_app/core/ui/adaptive/adaptive_top_bar.dart';
import 'package:marieum_app/features/speak/presentation/bloc/utterance_bloc.dart';

class MainNavigationShell extends StatelessWidget {
  const MainNavigationShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final locked = context.select<UtteranceBloc, bool>(
      (bloc) => bloc.state.phase.locksScreen,
    );
    return Scaffold(
      drawer: const AppDrawer(),
      drawerEnableOpenDragGesture: !locked,
      appBar: shell.currentIndex == 0
          ? null
          : AdaptiveTopBar(
              title: const ['말하기', '요청 기록', '설정'][shell.currentIndex],
              large:
                  shell.currentIndex != 0 &&
                  Theme.of(context).platform == TargetPlatform.iOS,
              leading: Builder(
                builder: (context) => IconButton(
                  tooltip: '메뉴 열기',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu_rounded),
                ),
              ),
            ),
      body: SafeArea(top: false, child: shell),
      bottomNavigationBar: IgnorePointer(
        ignoring: locked,
        child: ExcludeSemantics(
          excluding: locked,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: locked ? .45 : 1,
            child: AdaptiveTabBar(
              selectedIndex: shell.currentIndex,
              onSelected: (index) => shell.goBranch(
                index,
                initialLocation: index == shell.currentIndex,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
