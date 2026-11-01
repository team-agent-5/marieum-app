import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/feature_panel.dart';
import 'package:marieum_app/core/ui/key_text.dart';
import 'package:marieum_app/features/auth/domain/entities/auth_status.dart';
import 'package:marieum_app/features/auth/presentation/bloc/auth_bloc.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({required this.userId, super.key});
  final String userId;
  @override
  Widget build(BuildContext context) => FeaturePage(
    title: '계정 관리',
    child: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text('내 정보', style: AppTokens.copy),
        const SizedBox(height: 7),
        FeaturePanel(
          child: Column(
            children: [
              BlocSelector<AuthBloc, AuthState, String>(
                selector: (state) => switch (state.status) {
                  AuthAuthenticated(:final profile) => profile.nickname,
                  _ => '',
                },
                builder: (context, nickname) =>
                    _InfoRow(label: '닉네임', value: nickname),
              ),
              _InfoRow(
                label: '아이디',
                value: userId.isEmpty ? '—' : userId,
                action: const Text('변경 불가', style: AppTokens.copy),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text('로그인', style: AppTokens.copy),
        const SizedBox(height: 7),
        const FeaturePanel(
          child: ListTile(
            leading: Icon(Icons.lock_outline, color: AppTokens.primaryStrong),
            title: Text('이 기기에서 로그인 유지'),
            trailing: Text('365일'),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () =>
              context.read<AuthBloc>().add(const LogoutRequested()),
          icon: const Icon(Icons.logout_rounded),
          label: const KeyText('로그아웃'),
        ),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.action});
  final String label;
  final String value;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
    child: Row(
      children: [
        SizedBox(width: 66, child: Text(label, style: AppTokens.copy)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 6),
        ?action,
      ],
    ),
  );
}
