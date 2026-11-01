import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/tts/cloud_voice.dart';
import 'package:marieum_app/features/settings/domain/entities/app_settings.dart';
import 'package:marieum_app/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/pump_app.dart';

class _MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

void main() {
  late _MockSettingsCubit settings;

  setUpAll(() => registerFallbackValue(CloudVoice.female));

  Future<void> pump(WidgetTester tester, {required bool available}) async {
    settings = _MockSettingsCubit();
    whenListen(
      settings,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState(
        const AppSettings(),
        cloudVoiceAvailable: available,
      ),
    );
    when(() => settings.setCloudVoice(any())).thenAnswer((_) async {});
    final router = await tester.pumpApp(
      initialLocation: '/settings',
      settingsCubit: settings,
    );
    addTearDown(router.dispose);
  }

  group('cloud voice switch', () {
    testWidgets('switches between the female and male voice', (tester) async {
      await pump(tester, available: true);
      expect(find.byKey(const ValueKey('cloud_voice')), findsOneWidget);
      expect(find.text('인터넷이 안 될 때 목소리'), findsOneWidget);
      await tester.tap(find.text('남성'));
      await tester.pump();
      verify(() => settings.setCloudVoice(CloudVoice.male)).called(1);
    });

    testWidgets('is hidden without a gateway key', (tester) async {
      await pump(tester, available: false);
      expect(find.byKey(const ValueKey('cloud_voice')), findsNothing);
      expect(find.text('목소리'), findsOneWidget);
    });
  });
}
