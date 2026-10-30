import 'package:flutter/material.dart';

abstract final class AppTokens {
  static const bg = Color(0xFFF5F8FD);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceBlue = Color(0xFFEDF3FF);
  static const primary = Color(0xFF4F7DF3);
  static const primaryStrong = Color(0xFF3564D8);
  static const primarySoft = Color(0xFFDFE9FF);
  static const onTonal = Color(0xFF183B79);
  static const lavender = Color(0xFFF0EDFF);
  static const ink = Color(0xFF17233D);
  static const ink2 = Color(0xFF596780);
  static const ink3 = Color(0xFF8792A7);
  static const line = Color(0xFFD9E2F0);
  static const lineStrong = Color(0xFFBCC9DC);
  static const success = Color(0xFF2F8A68);
  static const successSoft = Color(0xFFE8F6EF);
  static const danger = Color(0xFFC53B45);
  static const dangerSoft = Color(0xFFFFF0F1);
  static const warning = Color(0xFFB56F1B);
  static const warningSoft = Color(0xFFFFF5E6);
  static const focus = Color(0xFFF1B800);

  static const fontFamily = 'Pretendard';
  static const pagePadding = 18.0;
  static const gap = 14.0;
  static const buttonHeight = 52.0;
  static const fieldHeight = 56.0;
  static const iconButtonSize = 44.0;
  static const cardRadius = 18.0;
  static const buttonRadius = 15.0;
  static const fieldRadius = 16.0;
  static const tabRadius = 33.0;
  static const tabHeight = 66.0;
  static const maxTextScale = 1.3;
  static const largeTextMultiplier = 1.25;

  static const title = TextStyle(
    fontSize: 24,
    height: 1.28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.36,
  );
  static const copy = TextStyle(fontSize: 15, height: 1.55, color: ink2);
  static const phrase = TextStyle(
    fontSize: 32,
    height: 1.25,
    fontWeight: FontWeight.w900,
    letterSpacing: -1.28,
  );
}
