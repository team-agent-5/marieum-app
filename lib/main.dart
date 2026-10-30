import 'package:flutter/widgets.dart';
import 'package:marieum_app/app/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrap();
}
