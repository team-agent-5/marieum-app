import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockPreferences extends Mock implements SharedPreferences {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group(PrefsStore, () {
    test('surfaces failed persistence instead of claiming success', () async {
      final plugin = _MockPreferences();
      when(() => plugin.setString(any(), any())).thenAnswer((_) async => false);
      final store = PrefsStore(SharedPrefsBackend(plugin));
      await expectLater(
        store.writeString(PrefsKeys.loginUserId, 'demo_a'),
        throwsA(isA<StorageFailure>()),
      );
    });
  });
}
