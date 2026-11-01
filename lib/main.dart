import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:marieum_app/app/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Large phrases and the speak button are laid out for portrait only.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await bootstrap();
}
