import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

void main() {
  testWidgets('keeps the greeting below the status bar', (tester) async {
    tester.view
      ..padding = const FakeViewPadding(top: 141)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = await tester.pumpApp();
    addTearDown(router.dispose);

    expect(tester.getTopLeft(find.text('김환자님')).dy, greaterThanOrEqualTo(47));
  });
}
