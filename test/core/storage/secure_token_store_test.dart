import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/core/storage/secure_token_store.dart';
import 'package:marieum_app/core/storage/token_vault.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockVault extends Mock implements TokenVault {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group(SecureTokenStore, () {
    late PrefsStore prefs;
    late _MockVault vault;
    late SecureTokenStore store;
    late String? token;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = PrefsStore(
        SharedPrefsBackend(await SharedPreferences.getInstance()),
      );
      vault = _MockVault();
      token = 'old-token';
      when(vault.clearAll).thenAnswer((_) async {
        token = null;
      });
      when(vault.read).thenAnswer((_) async => token);
      when(() => vault.write(any())).thenAnswer((call) async {
        token = call.positionalArguments.first as String;
      });
      when(vault.delete).thenAnswer((_) async {
        token = null;
      });
      store = SecureTokenStore(vault: vault, prefs: prefs);
    });
    test(
      'clears leftover keychain data before the first read '
      'and marks installation',
      () async {
        expect(await store.read(), isNull);
        expect(prefs.readBool(PrefsKeys.installationInitialized), isTrue);
        verifyInOrder([vault.clearAll, vault.read]);
      },
    );
    test('keeps tokens on an existing installation', () async {
      await prefs.writeBool(PrefsKeys.installationInitialized, value: true);
      expect(await store.read(), 'old-token');
      verifyNever(vault.clearAll);
    });
    test('coalesces concurrent initialization and reads', () async {
      expect(await Future.wait([store.read(), store.read(), store.read()]), [
        null,
        null,
        null,
      ]);
      verify(vault.clearAll).called(1);
    });
    test(
      'does not mark installation after failed cleanup and permits retry',
      () async {
        when(vault.clearAll).thenThrow(Exception('keychain locked'));
        await expectLater(store.initialize(), throwsA(isA<StorageFailure>()));
        expect(prefs.readBool(PrefsKeys.installationInitialized), isNull);
        when(vault.clearAll).thenAnswer((_) async {
          token = null;
        });
        await store.initialize();
        expect(prefs.readBool(PrefsKeys.installationInitialized), isTrue);
        verify(vault.clearAll).called(2);
      },
    );
    test('serializes token writes and logout cleanup', () async {
      await Future.wait([store.write('new-token'), store.clear()]);
      expect(await store.read(), isNull);
      verifyInOrder([() => vault.write('new-token'), vault.delete]);
    });
    test('recovers the operation queue after a failed read', () async {
      when(vault.read).thenThrow(Exception('locked'));
      await expectLater(store.read(), throwsA(isA<StorageFailure>()));
      await store.write('recovered');
      when(vault.read).thenAnswer((_) async => token);
      expect(await store.read(), 'recovered');
    });
  });
}
