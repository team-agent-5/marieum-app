import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/feature_panel.dart';
import 'package:marieum_app/core/ui/key_text.dart';
import 'package:marieum_app/features/quick_phrase/domain/entities/quick_phrase.dart';
import 'package:marieum_app/features/quick_phrase/presentation/bloc/quick_phrase_bloc.dart';
import 'package:marieum_app/features/quick_phrase/presentation/widgets/quick_phrase_icon.dart';

class QuickPhraseManagementPage extends StatefulWidget {
  const QuickPhraseManagementPage({super.key});
  @override
  State<QuickPhraseManagementPage> createState() =>
      _QuickPhraseManagementPageState();
}

class _QuickPhraseManagementPageState extends State<QuickPhraseManagementPage> {
  final _text = TextEditingController();
  bool _adding = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _cancel() {
    setState(() {
      _adding = false;
      _text.clear();
    });
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<QuickPhraseBloc, QuickPhraseState>(
        listenWhen: (previous, current) =>
            previous.status == QuickPhraseStatus.saving &&
            current.status == QuickPhraseStatus.saved,
        listener: (context, state) {
          if (_adding) _cancel();
        },
        builder: (context, state) => FeaturePage(
          title: _adding ? '빠른 문장 추가' : '빠른 문장 관리',
          onBack: _adding ? _cancel : null,
          child: _adding ? _form(context, state) : _list(context, state),
        ),
      );
  Widget _list(BuildContext context, QuickPhraseState state) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const Text('메인에 보이는 순서대로예요. 자주 쓰는 말을 더하거나 빼 보세요.', style: AppTokens.copy),
      const SizedBox(height: 14),
      FeaturePanel(
        child: Column(
          children: [
            for (final phrase in state.phrases)
              ListTile(
                leading: Icon(
                  quickPhraseIconData(phrase.icon),
                  color: AppTokens.primaryStrong,
                ),
                title: KeyText(
                  phrase.text,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                trailing: IconButton(
                  tooltip: '${phrase.text} 빼기',
                  onPressed:
                      state.canRemove &&
                          state.status != QuickPhraseStatus.saving
                      ? () => context.read<QuickPhraseBloc>().add(
                          QuickPhraseRemoved(phrase.id),
                        )
                      : null,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      FilledButton(
        onPressed:
            state.phrases.length >= QuickPhraseRules.maxCount ||
                state.status == QuickPhraseStatus.saving
            ? null
            : () => setState(() => _adding = true),
        child: const KeyText('문장 추가'),
      ),
    ],
  );
  Widget _form(BuildContext context, QuickPhraseState state) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const Text('문장', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      TextField(
        controller: _text,
        maxLength: QuickPhraseRules.maxLength,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: '따뜻한 물 주세요',
          helperText: '20자 이내로 짧고 또렷하게 적어요',
          errorText: state.status == QuickPhraseStatus.failure
              ? state.failure?.message
              : null,
          errorMaxLines: 3,
        ),
      ),
      const SizedBox(height: 24),
      const Text('메인에 이렇게 보여요', style: AppTokens.copy),
      const SizedBox(height: 10),
      FeaturePanel(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.short_text_rounded,
                color: AppTokens.primaryStrong,
              ),
              const SizedBox(height: 12),
              KeyText(
                _text.text.trim().isEmpty ? '따뜻한 물 주세요' : _text.text.trim(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text('눌러서 바로 재생', style: AppTokens.copy),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed:
            _text.text.trim().isEmpty ||
                state.status == QuickPhraseStatus.saving
            ? null
            : () => context.read<QuickPhraseBloc>().add(
                QuickPhraseAdded(_text.text),
              ),
        child: KeyText(
          state.status == QuickPhraseStatus.saving ? '저장 중…' : '저장',
        ),
      ),
      TextButton(
        onPressed: state.status == QuickPhraseStatus.saving ? null : _cancel,
        child: const Text('취소'),
      ),
    ],
  );
}
