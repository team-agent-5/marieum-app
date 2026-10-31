import 'package:flutter/material.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/feature_panel.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext context) => const FeaturePage(
    title: '개인정보·데이터',
    child: SingleChildScrollView(
      padding: EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('수집 안내', style: AppTokens.copy),
          SizedBox(height: 7),
          FeaturePanel(
            child: Column(
              children: [
                ListTile(
                  title: Text('음성 원본은 저장하지 않아요'),
                  subtitle: Text('녹음은 문장으로 바꾼 뒤 바로 지워져요.'),
                ),
                ListTile(
                  title: Text('내 데이터로만 추천해요'),
                  subtitle: Text('다른 사람의 데이터와 섞이지 않아요.'),
                ),
              ],
            ),
          ),
          SizedBox(height: 18),
          Text('내 기록', style: AppTokens.copy),
          SizedBox(height: 7),
          FeaturePanel(
            child: Column(
              children: [
                _Unavailable(label: '요청 기록 보관 기간', icon: Icons.history_rounded),
                _Unavailable(label: '내 데이터 내려받기', icon: Icons.download_rounded),
              ],
            ),
          ),
          SizedBox(height: 18),
          Text('삭제', style: AppTokens.copy),
          SizedBox(height: 7),
          FeaturePanel(
            child: Column(
              children: [
                _Unavailable(
                  label: '요청 기록 모두 삭제',
                  icon: Icons.delete_outline_rounded,
                ),
                _Unavailable(
                  label: '계정과 데이터 삭제',
                  icon: Icons.delete_forever_outlined,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.label, required this.icon});
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => ListTile(
    enabled: false,
    leading: Icon(icon),
    title: Text(label),
    subtitle: const Text('준비 중'),
  );
}
