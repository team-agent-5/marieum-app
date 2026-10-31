import 'package:flutter/material.dart';
import 'package:marieum_app/core/theme/tokens.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 54, super.key});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Marieum 로고',
    image: true,
    child: Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .18),
      decoration: BoxDecoration(
        color: AppTokens.primaryStrong,
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: const CustomPaint(painter: _MarkPainter()),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 64);
    final paint = Paint()
      ..color = AppTokens.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final bubble = Path()
      ..moveTo(14, 15)
      ..lineTo(50, 15)
      ..quadraticBezierTo(56, 15, 56, 21)
      ..lineTo(56, 44)
      ..quadraticBezierTo(56, 50, 50, 50)
      ..lineTo(32, 50)
      ..lineTo(21, 58)
      ..lineTo(21, 50)
      ..lineTo(14, 50)
      ..quadraticBezierTo(8, 50, 8, 44)
      ..lineTo(8, 21)
      ..quadraticBezierTo(8, 15, 14, 15);
    final wave = Path()
      ..moveTo(18, 33)
      ..lineTo(25, 33)
      ..lineTo(29, 24)
      ..lineTo(35, 42)
      ..lineTo(40, 30)
      ..lineTo(43, 36)
      ..lineTo(48, 36);
    canvas
      ..drawPath(bubble, paint)
      ..drawPath(wave, paint);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}
