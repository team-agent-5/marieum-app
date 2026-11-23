import 'dart:async';

import 'package:flutter/material.dart';
import 'package:marieum_app/core/theme/tokens.dart';
import 'package:marieum_app/core/ui/adaptive/adaptive_top_bar.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ListenQrScanner extends StatefulWidget {
  const ListenQrScanner({super.key});

  @override
  State<ListenQrScanner> createState() => _ListenQrScannerState();
}

class _ListenQrScannerState extends State<ListenQrScanner> {
  final _controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _returned = false;

  void _detect(BarcodeCapture capture) {
    if (_returned || ModalRoute.of(context)?.isCurrent != true) return;
    for (final barcode in capture.barcodes) {
      final payload = barcode.rawValue;
      if (payload == null || payload.isEmpty) continue;
      _returned = true;
      Navigator.of(context).pop(payload);
      return;
    }
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AdaptiveTopBar(
      title: 'QR 찍기',
      leading: IconButton(
        tooltip: '뒤로',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ),
    body: SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _detect,
              errorBuilder: (_, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.pagePadding),
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? '카메라 권한을 허용하거나 연결 코드를 입력해 주세요'
                        : '카메라를 열 수 없어요. 연결 코드를 입력해 주세요',
                    style: AppTokens.title,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppTokens.pagePadding),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, AppTokens.buttonHeight),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('코드 입력으로 돌아가기'),
            ),
          ),
        ],
      ),
    ),
  );
}
