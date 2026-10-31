import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/core/network/api_client.dart';
import 'package:marieum_app/features/quick_phrase/data/dto/preset_receipt_dto.dart';
import 'package:marieum_app/features/quick_phrase/domain/entities/preset_receipt.dart';

// Kept as an interface so remote and mock sources can be swapped.
// ignore: one_member_abstracts
abstract interface class PresetDataSource {
  Future<Result<PresetReceipt>> usePreset(int presetIndex);
}

class RemotePresetDataSource implements PresetDataSource {
  RemotePresetDataSource(this._client);
  final ApiClient _client;
  @override
  Future<Result<PresetReceipt>> usePreset(int presetIndex) => _client.request(
    '/phrase/preset',
    method: 'POST',
    data: {'preset_index': presetIndex},
    decode: PresetReceiptDto.fromJson,
  );
}
