import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/marieum_app.dart';
import 'package:marieum_app/core/config/app_config.dart';
import 'package:marieum_app/core/di/dependencies.dart';
import 'package:marieum_app/features/auth/presentation/bloc/auth_bloc.dart';

Future<void> bootstrap() async {
  final dependencies = await configureDependencies();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['Pretendard'],
      await rootBundle.loadString('assets/fonts/OFL.txt'),
    );
  });
  runApp(
    BlocProvider.value(
      value: dependencies<AuthBloc>(),
      child: MarieumApp(
        config: dependencies<AppConfig>(),
        router: dependencies<GoRouter>(),
      ),
    ),
  );
}
