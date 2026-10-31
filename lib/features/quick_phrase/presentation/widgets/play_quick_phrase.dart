import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:marieum_app/app/router/app_routes.dart';
import 'package:marieum_app/features/quick_phrase/domain/entities/quick_phrase.dart';
import 'package:marieum_app/features/quick_phrase/presentation/bloc/quick_phrase_bloc.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';

/// Speaks the phrase right away and records its use in the background.
void playQuickPhrase(BuildContext context, QuickPhrase phrase) {
  context.read<QuickPhraseBloc>().add(QuickPhraseUsed(phrase));
  unawaited(
    context.push<void>(
      AppRoutes.playback,
      extra: PlaybackRequest(
        text: phrase.text,
        origin: PlaybackOrigin.quickPhrase,
      ),
    ),
  );
}
