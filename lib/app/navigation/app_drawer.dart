import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/router/app_routes.dart';
import 'package:marieum_app/core/theme/tokens.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppTokens.surfaceBlue,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          children: const [
            Padding(
              padding: EdgeInsets.all(12),
              child: Text('Marieum', style: AppTokens.title),
            ),
            _SectionTitle('바로가기'),
            _DrawerLink(
              label: '요청 기록',
              icon: Icons.list_alt_rounded,
              path: AppRoutes.history,
              tab: true,
            ),
            _DrawerLink(
              label: '설정',
              icon: Icons.settings_outlined,
              path: AppRoutes.settings,
              tab: true,
            ),
            _SectionTitle('내 말하기'),
            _DrawerLink(
              label: '빠른 문장 관리',
              icon: Icons.text_fields_rounded,
              path: AppRoutes.quickPhrases,
            ),
            _DrawerLink(
              label: '개인화 현황',
              icon: Icons.insights_outlined,
              path: AppRoutes.insight,
            ),
            _SectionTitle('최근 요청'),
            Divider(),
            _DrawerLink(
              label: '사용 방법 다시 보기',
              icon: Icons.help_outline_rounded,
              path: '${AppRoutes.onboarding}?review=1',
            ),
            _DrawerLink(
              label: '계정 관리',
              icon: Icons.person_outline_rounded,
              path: AppRoutes.account,
            ),
            _DrawerLink(
              label: '개인정보·데이터',
              icon: Icons.lock_outline_rounded,
              path: AppRoutes.privacy,
            ),
            ListTile(
              enabled: false,
              leading: Icon(Icons.logout_rounded),
              title: Text('로그아웃'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
      child: Text(
        title,
        style: const TextStyle(fontSize: 12, color: AppTokens.ink3),
      ),
    );
  }
}

class _DrawerLink extends StatelessWidget {
  const _DrawerLink({
    required this.label,
    required this.icon,
    required this.path,
    this.tab = false,
  });

  final String label;
  final IconData icon;
  final String path;
  final bool tab;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTokens.primaryStrong),
      title: Text(label),
      onTap: () {
        Navigator.of(context).pop();
        if (tab) {
          context.go(path);
        } else {
          unawaited(context.push<void>(path));
        }
      },
    );
  }
}
