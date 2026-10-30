import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/main.dart';

void main() {
  testWidgets('앱 기본 화면이 표시된다', (tester) async {
    await tester.pumpWidget(const MarieumApp());
    expect(find.text('말이음'), findsOneWidget);
  });
}
