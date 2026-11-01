import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/app/navigation/app_drawer.dart';
import 'package:marieum_app/app/navigation/push_drawer.dart';

import '../../helpers/pump_app.dart';

void main() {
  Finder pane() => find.byKey(const ValueKey('push_drawer_pane'));

  double paneShift(WidgetTester tester) =>
      tester.widget<Transform>(pane()).transform.getTranslation().x;

  Future<void> setScreen(
    WidgetTester tester,
    Size size, {
    double bottomInset = 34,
  }) async {
    tester.view
      ..physicalSize = size * 3
      ..devicePixelRatio = 3
      ..padding = FakeViewPadding(top: 47 * 3, bottom: bottomInset * 3);
    addTearDown(tester.view.reset);
  }

  group(PushDrawer, () {
    test('drawer width follows 80% of the screen within 280..320', () {
      expect(PushDrawer.drawerWidthFor(320), 280);
      expect(PushDrawer.drawerWidthFor(375), 300);
      expect(PushDrawer.drawerWidthFor(430), 320);
    });

    testWidgets('pushes the main pane right without moving it vertically', (
      tester,
    ) async {
      await setScreen(tester, const Size(390, 844));
      final router = await tester.pumpApp();
      addTearDown(router.dispose);
      final closedTop = tester.getTopLeft(find.text('김환자님')).dy;
      expect(paneShift(tester), 0);
      expect(find.byType(AppDrawer), findsNothing);

      await tester.tap(find.byTooltip('메뉴 열기'));
      await tester.pumpAndSettle();

      expect(paneShift(tester), PushDrawer.drawerWidthFor(390) - 8);
      expect(tester.getTopLeft(find.text('김환자님')).dy, closedTop);
      expect(find.byType(AppDrawer), findsOneWidget);
      expect(find.text('Marieum'), findsNothing);
      expect(find.text('@demo_a'), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
    });

    testWidgets('swipes open from the left edge and swipes closed', (
      tester,
    ) async {
      await setScreen(tester, const Size(390, 844));
      final router = await tester.pumpApp();
      addTearDown(router.dispose);

      await tester.flingFrom(const Offset(8, 400), const Offset(200, 0), 800);
      await tester.pumpAndSettle();
      expect(paneShift(tester), PushDrawer.drawerWidthFor(390) - 8);

      await tester.flingFrom(
        const Offset(360, 400),
        const Offset(-200, 0),
        800,
      );
      await tester.pumpAndSettle();
      expect(paneShift(tester), 0);
      expect(find.byType(AppDrawer), findsNothing);
    });

    testWidgets('a short slow drag springs back', (tester) async {
      await setScreen(tester, const Size(390, 844));
      final router = await tester.pumpApp();
      addTearDown(router.dispose);

      final gesture = await tester.startGesture(const Offset(8, 400));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(paneShift(tester), 0);
    });

    testWidgets('tapping the pushed pane closes without hitting its widgets', (
      tester,
    ) async {
      await setScreen(tester, const Size(390, 844));
      final router = await tester.pumpApp();
      addTearDown(router.dispose);
      await tester.tap(find.byTooltip('메뉴 열기'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(370, 500));
      await tester.pumpAndSettle();
      expect(paneShift(tester), 0);
      expect(find.byType(AppDrawer), findsNothing);
      expect(router.state.uri.path, '/speak');
    });

    testWidgets('back closes the drawer before leaving the screen', (
      tester,
    ) async {
      await setScreen(tester, const Size(390, 844));
      final router = await tester.pumpApp();
      addTearDown(router.dispose);
      await tester.tap(find.byTooltip('메뉴 열기'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(paneShift(tester), 0);
      expect(router.state.uri.path, '/speak');
    });

    testWidgets('a menu entry navigates and leaves the drawer closed', (
      tester,
    ) async {
      await setScreen(tester, const Size(390, 844));
      final router = await tester.pumpApp();
      addTearDown(router.dispose);
      await tester.tap(find.byTooltip('메뉴 열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('개인화 현황'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/insight');
      router.pop();
      await tester.pumpAndSettle();
      expect(paneShift(tester), 0);
    });

    testWidgets('logout is reachable on a short screen with large text', (
      tester,
    ) async {
      await setScreen(tester, const Size(375, 640));
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final router = await tester.pumpApp();
      addTearDown(router.dispose);
      await tester.tap(find.byTooltip('메뉴 열기'));
      await tester.pumpAndSettle();

      final logout = find.text('로그아웃');
      await tester.scrollUntilVisible(
        logout,
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('app_drawer_scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final bottom = tester.getBottomLeft(logout).dy;
      expect(bottom, lessThanOrEqualTo(640 - 34));
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the footer at the bottom on a tall screen', (
      tester,
    ) async {
      await setScreen(tester, const Size(430, 932));
      final router = await tester.pumpApp();
      addTearDown(router.dispose);
      await tester.tap(find.byTooltip('메뉴 열기'));
      await tester.pumpAndSettle();
      final logoutBottom = tester.getBottomLeft(find.text('로그아웃')).dy;
      expect(logoutBottom, greaterThan(932 - 34 - 22 - 16 - 44));
      expect(logoutBottom, lessThanOrEqualTo(932 - 34));
    });

    testWidgets('animates over 340ms when motion is allowed', (tester) async {
      await setScreen(tester, const Size(390, 844));
      final router = await tester.pumpApp(reduceMotion: false, settle: false);
      addTearDown(router.dispose);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('메뉴 열기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 170));
      final mid = paneShift(tester);
      expect(mid, greaterThan(0));
      expect(mid, lessThan(PushDrawer.drawerWidthFor(390) - 8));
      await tester.pump(const Duration(milliseconds: 200));
      expect(paneShift(tester), PushDrawer.drawerWidthFor(390) - 8);
    });
  });
}
