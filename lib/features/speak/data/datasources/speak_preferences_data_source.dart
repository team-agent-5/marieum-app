import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/network/api_client.dart';
import 'package:marieum_app/features/speak/domain/entities/speak_mode.dart';

// Kept as an interface so remote and mock sources can be swapped.
// ignore: one_member_abstracts
abstract interface class SpeakPreferencesDataSource {
  Future<Result<void>> mirrorMode(SpeakMode mode);
}

class RemoteSpeakPreferencesDataSource implements SpeakPreferencesDataSource {
  RemoteSpeakPreferencesDataSource(this._client);
  final ApiClient _client;
  @override
  Future<Result<void>> mirrorMode(SpeakMode mode) => _client.request(
    '/patient/preferences',
    method: 'PATCH',
    data: {'realtime_mode': mode == SpeakMode.live},
    decode: (_) {},
  );
}

class MockSpeakPreferencesDataSource implements SpeakPreferencesDataSource {
  @override
  Future<Result<void>> mirrorMode(SpeakMode mode) async => const Success(null);
}
