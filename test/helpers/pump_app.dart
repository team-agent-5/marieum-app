import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/marieum_app.dart';
import 'package:marieum_app/app/router/app_router.dart';
import 'package:marieum_app/core/config/app_config.dart';

extension PumpApp on WidgetTester {
  Future<GoRouter> pumpApp({
    String initialLocation = '/speak',
    bool showSafetyBanner = false,
  }) async {
    final router = createAppRouter(initialLocation: initialLocation);
    await pumpWidget(
      MarieumApp(
        config: AppConfig(
          baseUrl: '',
          wsUrl: '',
          useMock: true,
          showSafetyBanner: showSafetyBanner,
        ),
        router: router,
      ),
    );
    await pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    return router;
  }
}
