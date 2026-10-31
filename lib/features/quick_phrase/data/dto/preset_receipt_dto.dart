import 'package:marieum_app/features/quick_phrase/domain/entities/preset_receipt.dart';

abstract final class PresetReceiptDto {
  static PresetReceipt fromJson(Object? json) {
    final body = json! as Map<String, Object?>;
    final id = body['log_id'];
    final text = body['final_text'];
    final index = body['preset_index'];
    if ((id is! String && id is! int) ||
        text is! String ||
        text.trim().isEmpty ||
        index is! int ||
        index < 1 ||
        index > 10) {
      throw const FormatException('Invalid preset receipt.');
    }
    return PresetReceipt(
      logId: id.toString(),
      finalText: text,
      presetIndex: index,
    );
  }
}
