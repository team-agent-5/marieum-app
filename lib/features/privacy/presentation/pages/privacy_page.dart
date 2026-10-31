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
        ],
      ),
    ),
  );
}
