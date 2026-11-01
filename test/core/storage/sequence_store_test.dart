import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/storage/prefs_store.dart';
import 'package:marieum_app/core/storage/sequence_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group(SequenceStore, () {
    late PrefsStore prefs;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = PrefsStore(
        SharedPrefsBackend(await SharedPreferences.getInstance()),
      );
    });
    test(
      'persists the latest opaque ID across store instances and clears it',
      () async {
        final store = SequenceStore(prefs);
        expect(store.lastLogId, isNull);
        await store.save('42');
        await store.save('uuid-log-id');
        expect(SequenceStore(prefs).lastLogId, 'uuid-log-id');
        await store.clear();
        expect(SequenceStore(prefs).lastLogId, isNull);
      },
    );
    test(
      'keeps settings and login ID when clearing per-user sequence state',
      () async {
        await prefs.writeString(PrefsKeys.ttsRate, 'slow');
        await prefs.writeString(PrefsKeys.ttsVolume, 'soft');
        await prefs.writeString(PrefsKeys.speakMode, 'live');
        await prefs.writeBool(PrefsKeys.largeText, value: true);
        await prefs.writeString(PrefsKeys.loginUserId, 'demo_a');
        await SequenceStore(prefs).save('123');
        await SequenceStore(prefs).clear();
        expect(prefs.readString(PrefsKeys.ttsRate), 'slow');
        expect(prefs.readString(PrefsKeys.ttsVolume), 'soft');
        expect(prefs.readString(PrefsKeys.speakMode), 'live');
        expect(prefs.readBool(PrefsKeys.largeText), isTrue);
        expect(prefs.readString(PrefsKeys.loginUserId), 'demo_a');
      },
    );
  });
}
