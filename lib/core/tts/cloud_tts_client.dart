import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:marieum_app/core/tts/cloud_voice.dart';

/// Synthesizes speech through the foundation media gateway.
class CloudTtsClient {
  CloudTtsClient({required this._apiKey, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://copa.codyssey.kr',
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 15),
            ),
          );

  static const model = 'gemini-2.5-flash-tts';

  final String _apiKey;
  final Dio _dio;

  bool get isConfigured => _apiKey.isNotEmpty;

  Future<Uint8List> synthesize(String text, CloudVoice voice) async {
    final response = await _dio.post<Map<String, Object?>>(
      '/api/v1/audio/tts',
      data: {
        'model': model,
        'input': text,
        'voice': voice.id,
        'format': 'wav',
        'response_format': 'b64_json',
      },
      options: Options(headers: {'Authorization': 'Bearer $_apiKey'}),
    );
    final result = response.data?['result'];
    final encoded = result is Map ? result['b64_json'] : null;
    if (encoded is! String || encoded.isEmpty) {
      throw const FormatException('No audio in the response.');
    }
    return base64Decode(encoded);
  }
}
