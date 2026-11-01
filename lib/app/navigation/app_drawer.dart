import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/navigation/push_drawer.dart';
import 'package:marieum_app/app/router/app_routes.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';
import 'package:marieum_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:marieum_app/features/history/presentation/widgets/recent_requests_section.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-0.34, -0.94),
          end: Alignment(0.34, 0.94),
          colors: [Color(0xFFE4EDFB), Color(0xFFD8E5FA)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) => ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              key: const ValueKey('app_drawer_scroll'),
              padding: EdgeInsets.fromLTRB(14, 12, 14, 22 + bottomInset + 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      (constraints.maxHeight - 12 - 22 - bottomInset - 16)
                          .clamp(0, double.infinity),
                ),
                child: const IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Profile(),
                      SizedBox(height: 14),
                      _GroupTitle('바로가기'),
                      DrawerItem(
                        label: '요청 기록',
                        icon: Icons.list_alt_outlined,
                        path: AppRoutes.history,
                        tab: true,
                      ),
                      DrawerItem(
                        label: '설정',
                        icon: Icons.settings_outlined,
                        path: AppRoutes.settings,
                        tab: true,
                      ),
                      SizedBox(height: 10),
                      _GroupTitle('내 말하기'),
                      DrawerItem(
                        label: '빠른 문장 관리',
                        icon: Icons.text_fields_outlined,
                        path: AppRoutes.quickPhrases,
                      ),
                      DrawerItem(
                        label: '개인화 현황',
                        icon: Icons.insights_outlined,
                        path: AppRoutes.insight,
                      ),
                      SizedBox(height: 10),
                      _GroupTitle('최근 요청'),
                      _RecentRequests(),
                      Spacer(),
                      SizedBox(height: 12),
                      _Footer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Profile extends StatelessWidget {
  const _Profile();

  @override
  Widget build(BuildContext context) {
    final profile = context.select<AuthBloc, ({String nickname, String id})?>(
      (bloc) => switch (bloc.state.status) {
        AuthAuthenticated(:final profile) => (
          nickname: profile.nickname,
          id: profile.userId,
        ),
        _ => null,
      },
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            profile?.nickname ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: AppTokens.ink,
            ),
          ),
          if (profile != null && profile.id.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '@${profile.id}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppTokens.ink2),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentRequests extends StatelessWidget {
  const _RecentRequests();

  @override
  Widget build(BuildContext context) => RecentRequestsSection(
    onSelected: (text) {
      PushDrawerScope.of(context).close(animate: false);
      unawaited(
        context.push<void>(
          AppRoutes.playback,
          extra: PlaybackRequest(text: text, origin: PlaybackOrigin.history),
        ),
      );
    },
  );
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 10, bottom: 4),
    child: Semantics(
      header: true,
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppTokens.ink3,
        ),
      ),
    ),
  );
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0x1417233D))),
    ),
    child: Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DrawerItem(
            label: '사용 방법 다시 보기',
            icon: Icons.help_outline,
            path: '${AppRoutes.onboarding}?review=1',
          ),
          const DrawerItem(
            label: '계정 관리',
            icon: Icons.person_outline,
            path: AppRoutes.account,
          ),
          const DrawerItem(
            label: '개인정보·데이터',
            icon: Icons.lock_outline,
            path: AppRoutes.privacy,
          ),
          DrawerRow(
            label: '로그아웃',
            icon: Icons.logout_outlined,
            color: AppTokens.danger,
            onTap: () {
              PushDrawerScope.of(context).close(animate: false);
              context.read<AuthBloc>().add(const LogoutRequested());
            },
          ),
        ],
      ),
    ),
  );
}

/// A drawer entry that navigates and leaves the drawer closed.
class DrawerItem extends StatelessWidget {
  const DrawerItem({
    required this.label,
    required this.icon,
    required this.path,
    this.tab = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final String path;

  /// Tabs switch in place; other entries open on top of the shell.
  final bool tab;

  @override
  Widget build(BuildContext context) => DrawerRow(
    label: label,
    icon: icon,
    onTap: () {
      final drawer = PushDrawerScope.of(context);
      if (tab) {
        drawer.close();
        context.go(path);
      } else {
        drawer.close(animate: false);
        unawaited(context.push<void>(path));
      }
    },
  );
}

class DrawerRow extends StatelessWidget {
  const DrawerRow({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color = AppTokens.ink,
    this.iconColor,
    this.iconSize = 24,
    this.textStyle,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color? iconColor;
  final double iconSize;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Icon(
                  icon,
                  size: iconSize,
                  color:
                      iconColor ??
                      (color == AppTokens.ink
                          ? AppTokens.primaryStrong
                          : color),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      textStyle ??
                      TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
