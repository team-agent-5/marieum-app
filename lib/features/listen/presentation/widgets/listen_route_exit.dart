import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ListenRouteExit extends StatefulWidget {
  const ListenRouteExit({
    required this.cleanup,
    required this.fallback,
    required this.builder,
    super.key,
  });

  final Future<void> Function() cleanup;
  final String fallback;
  final Widget Function(VoidCallback onClose) builder;

  @override
  State<ListenRouteExit> createState() => _ListenRouteExitState();
}

class _ListenRouteExitState extends State<ListenRouteExit> {
  bool _closing = false;

  Future<void> _close() async {
    if (_closing) return;
    FocusScope.of(context).unfocus();
    setState(() => _closing = true);
    try {
      await widget.cleanup();
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        context.go(widget.fallback);
      }
    } catch (_) {
      if (mounted) setState(() => _closing = false);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: AbsorbPointer(absorbing: _closing, child: widget.builder(_close)),
  );
}
