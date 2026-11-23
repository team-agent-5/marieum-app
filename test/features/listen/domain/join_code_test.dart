import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/listen/domain/entities/listen_session.dart';

void main() {
  group(JoinCode, () {
    test('normalize upper-cases and drops spaces and dashes', () {
      expect(JoinCode.normalize('k7q 2mx'), 'K7Q2MX');
      expect(JoinCode.normalize('K7Q-2MX'), 'K7Q2MX');
    });

    test('normalize refuses wrong lengths and confusable characters', () {
      expect(JoinCode.normalize('K7Q2M'), isNull);
      expect(JoinCode.normalize('K7Q2MXA'), isNull);
      for (final bad in ['K7Q2M0', 'K7Q2MO', 'K7Q2M1', 'K7Q2MI', 'K7Q2M!']) {
        expect(JoinCode.normalize(bad), isNull, reason: bad);
      }
    });

    test('the QR payload round-trips and other QR codes are refused', () {
      expect(JoinCode.fromScan(JoinCode.qrPayload('K7Q2MX')), 'K7Q2MX');
      expect(JoinCode.fromScan('K7Q2MX'), isNull);
      expect(JoinCode.fromScan('https://example.com'), isNull);
      expect(JoinCode.fromScan('marieum:listen:K7Q2M0'), isNull);
    });
  });
}
