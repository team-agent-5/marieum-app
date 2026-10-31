import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/adaptive/adaptive_top_bar.dart';
import 'package:marieum_app/features/auth/presentation/cubit/auth_form_state.dart';
import 'package:marieum_app/features/auth/presentation/widgets/brand_mark.dart';

typedef AuthFormInput = ({
  String userId,
  String password,
  String passwordConfirm,
  String nickname,
});

class AuthFormView extends StatefulWidget {
  const AuthFormView({
    required this.state,
    required this.onSubmit,
    this.signup = false,
    super.key,
  });
  final AuthFormState state;
  final ValueChanged<AuthFormInput> onSubmit;
  final bool signup;
  @override
  State<AuthFormView> createState() => _AuthFormViewState();
}

class _AuthFormViewState extends State<AuthFormView> {
  final _id = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _nickname = TextEditingController();
  @override
  void dispose() {
    _id.dispose();
    _password.dispose();
    _confirm.dispose();
    _nickname.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    widget.onSubmit((
      userId: _id.text,
      password: _password.text,
      passwordConfirm: _confirm.text,
      nickname: _nickname.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final signup = widget.signup;
    final state = widget.state;
    return Scaffold(
      appBar: AdaptiveTopBar(
        title: signup ? '회원가입' : '로그인',
        leading: signup
            ? IconButton(
                tooltip: '뒤로',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.go('/login'),
              )
            : null,
      ),
      body: SafeArea(
        top: false,
        child: AutofillGroup(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (state.status == AuthFormStatus.submitting) {
                return AuthLoading(signup: signup);
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 6),
                    const Center(child: BrandMark()),
                    const SizedBox(height: 8),
                    const Text(
                      'Marieum',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppTokens.ink,
                      ),
                    ),
                    Text(
                      signup ? '새 계정을 만들어요' : '다시 만나서 반가워요',
                      textAlign: TextAlign.center,
                      style: AppTokens.copy,
                    ),
                    const SizedBox(height: 20),
                    if (signup)
                      _AuthField(
                        label: '닉네임',
                        name: 'nickname',
                        controller: _nickname,
                        helper: '서비스에서 사용할 이름 · 1~16자',
                        error: state.fieldErrors['nickname'],
                        autofill: const [AutofillHints.nickname],
                      ),
                    _AuthField(
                      label: '아이디',
                      name: 'user_id',
                      controller: _id,
                      helper: signup ? '영문·숫자·밑줄 4~20자' : null,
                      asciiOnly: true,
                      error: state.fieldErrors['user_id'],
                      autofill: const [AutofillHints.username],
                    ),
                    _AuthField(
                      label: '비밀번호',
                      name: 'password',
                      controller: _password,
                      helper: signup ? '8자 이상' : null,
                      secret: true,
                      asciiOnly: true,
                      error: state.fieldErrors['password'],
                      autofill: [
                        if (signup)
                          AutofillHints.newPassword
                        else
                          AutofillHints.password,
                      ],
                    ),
                    if (signup)
                      _AuthField(
                        label: '비밀번호 확인',
                        name: 'password_confirm',
                        controller: _confirm,
                        secret: true,
                        asciiOnly: true,
                        error: state.fieldErrors['password_confirm'],
                        autofill: const [AutofillHints.newPassword],
                      ),
                    if (state.failure != null && state.fieldErrors.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          state.failure!.message,
                          style: const TextStyle(color: AppTokens.danger),
                          semanticsLabel: '오류: ${state.failure!.message}',
                        ),
                      ),
                    const SizedBox(height: 5),
                    FilledButton(
                      key: const ValueKey('auth_submit'),
                      onPressed: _submit,
                      child: Text(signup ? '회원가입' : '로그인'),
                    ),
                    if (!signup)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('처음이신가요?'),
                          TextButton(
                            onPressed: () => context.go('/signup'),
                            child: const Text('회원가입'),
                          ),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.label,
    required this.name,
    required this.controller,
    required this.autofill,
    this.helper,
    this.error,
    this.secret = false,
    this.asciiOnly = false,
  });
  final String label;
  final String name;
  final TextEditingController controller;
  final List<String> autofill;
  final String? helper;
  final String? error;
  final bool secret;

  /// Uses an ASCII keyboard so IDs and passwords are not composed in Hangul.
  final bool asciiOnly;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTokens.ink,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          key: ValueKey('auth_$name'),
          controller: controller,
          obscureText: secret,
          keyboardType: asciiOnly ? TextInputType.visiblePassword : null,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: autofill,
          textInputAction: TextInputAction.next,
          style: const TextStyle(fontSize: 16, color: AppTokens.ink),
          decoration: InputDecoration(
            errorText: error == null || error!.isEmpty ? null : error,
            error: error != null && error!.isEmpty
                ? const SizedBox.shrink()
                : null,
            helperText: error == null ? helper : null,
            helperStyle: const TextStyle(fontSize: 12, color: AppTokens.ink2),
            errorMaxLines: 3,
            isDense: true,
          ),
        ),
      ],
    ),
  );
}

class AuthLoading extends StatelessWidget {
  const AuthLoading({required this.signup, super.key});
  final bool signup;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                signup
                    ? Icons.person_outline_rounded
                    : Icons.lock_outline_rounded,
                color: AppTokens.primaryStrong,
                size: 38,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      signup ? '계정을 만들고 있어요' : '안전하게 로그인하고 있어요',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTokens.ink,
                      ),
                    ),
                    Text(
                      signup ? '입력한 정보를 확인하는 중이에요' : '암호화된 로그인 정보를 확인하는 중이에요',
                      style: AppTokens.copy,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          LinearProgressIndicator(
            value: MediaQuery.disableAnimationsOf(context) ? .45 : null,
          ),
          const SizedBox(height: 22),
          for (var i = 0; i < (signup ? 5 : 3); i++)
            Container(
              height: 56,
              margin: const EdgeInsets.only(bottom: 13),
              decoration: BoxDecoration(
                color: i == (signup ? 4 : 2)
                    ? AppTokens.primarySoft
                    : AppTokens.surfaceBlue,
                borderRadius: BorderRadius.circular(15),
              ),
            ),
        ],
      ),
    ),
  );
}
