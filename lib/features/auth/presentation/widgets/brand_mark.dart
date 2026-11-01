import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 54, super.key});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Marieum 로고',
    image: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size * .26),
      child: Image.asset(
        'assets/branding/marieum_logo.png',
        width: size,
        height: size,
        excludeFromSemantics: true,
      ),
    ),
  );
}
