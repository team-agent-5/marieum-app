import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/features/listen/domain/entities/listen_session.dart';
import 'package:marieum_app/features/listen/presentation/cubit/listener_cubit.dart';
import 'package:marieum_app/features/listen/presentation/widgets/listen_qr_scanner.dart';
import 'package:marieum_app/features/listen/presentation/widgets/listen_screen.dart';

class ListenerCodeForm extends StatefulWidget {
  const ListenerCodeForm({required this.error, super.key});

  final String? error;

  @override
  State<ListenerCodeForm> createState() => _ListenerCodeFormState();
}

class _ListenerCodeFormState extends State<ListenerCodeForm> {
  final _code = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_code.text.length != JoinCode.length) return;
    _focus.unfocus();
    await context.read<ListenerCubit>().join(_code.text);
  }

  Future<void> _scan() async {
    _focus.unfocus();
    final payload = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ListenQrScanner()),
    );
    if (payload != null && mounted) {
      await context.read<ListenerCubit>().joinScanned(payload);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('연결 코드 6자리를 입력해 주세요', style: AppTokens.title),
      const SizedBox(height: 16),
      ListenableBuilder(
        listenable: Listenable.merge([_code, _focus]),
        builder: (context, _) {
          final code = _code.text;
          final cursor = _code.selection.extentOffset.clamp(
            0,
            JoinCode.length - 1,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The cells share one editable field for native paste, selection,
              // and screen reader support.
              Stack(
                children: [
                  ExcludeSemantics(
                    child: Row(
                      spacing: 6,
                      children: [
                        for (var index = 0; index < JoinCode.length; index++)
                          Expanded(
                            child: Container(
                              alignment: Alignment.center,
                              constraints: const BoxConstraints(
                                minHeight: AppTokens.fieldHeight,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTokens.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _focus.hasFocus && index == cursor
                                      ? AppTokens.primaryStrong
                                      : AppTokens.lineStrong,
                                  width: _focus.hasFocus && index == cursor
                                      ? 2
                                      : 1,
                                ),
                              ),
                              child: Text(
                                index < code.length ? code[index] : ' ',
                                style: const TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: Semantics(
                      label: '연결 코드 6자리',
                      child: TextField(
                        controller: _code,
                        focusNode: _focus,
                        keyboardType: TextInputType.visiblePassword,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.go,
                        autocorrect: false,
                        enableSuggestions: false,
                        showCursor: false,
                        style: const TextStyle(color: Colors.transparent),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp('[a-zA-Z0-9]'),
                          ),
                          LengthLimitingTextInputFormatter(JoinCode.length),
                          TextInputFormatter.withFunction(
                            (_, value) =>
                                value.copyWith(text: value.text.toUpperCase()),
                          ),
                        ],
                        onSubmitted: (_) async => _join(),
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.error case final error?) ...[
                const SizedBox(height: 10),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: const TextStyle(
                      color: AppTokens.danger,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                style: ListenScreen.primaryButton,
                onPressed: code.length == JoinCode.length ? _join : null,
                child: const Text('연결하기'),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        style: ListenScreen.secondaryButton,
        onPressed: _scan,
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('QR 찍기'),
      ),
    ],
  );
}
