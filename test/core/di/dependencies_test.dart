import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/core/config/app_config.dart';
import 'package:marieum_app/core/di/dependencies.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('configureDependencies', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      SharedPreferences.setMockInitialValues({'rate': 'slow'});
    });

    test(
      'loads persisted preferences and registers one disposable router',
      () async {
        const config = AppConfig(baseUrl: '', wsUrl: '', useMock: true);
        final dependencies = await configureDependencies(config: config);
        addTearDown(dependencies.reset);
        expect(dependencies<SharedPreferences>().getString('rate'), 'slow');
        expect(identical(dependencies<AppConfig>(), config), isTrue);
        expect(
          identical(dependencies<GoRouter>(), dependencies<GoRouter>()),
          isTrue,
        );
      },
    );
  });
}
