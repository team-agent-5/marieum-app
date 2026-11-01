import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/app/navigation/app_drawer.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/history/domain/entities/history_entry.dart';
import 'package:marieum_app/features/history/domain/repositories/history_repository.dart';
import 'package:marieum_app/features/history/presentation/widgets/recent_requests_section.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/presentation/cubit/playback_cubit.dart';
import 'package:mocktail/mocktail.dart';
import '../../../../helpers/pump_app.dart';

class _MockHistory extends Mock implements HistoryRepository {}

class _MockPlayback extends MockCubit<PlaybackState> implements PlaybackCubit {}

void main() {
  group(RecentRequestsSection, () {
    testWidgets('replays a recent request locally after closing the drawer', (
      tester,
    ) async {
      final repository = _MockHistory();
      final playback = _MockPlayback();
      when(repository.recent).thenAnswer(
        (_) async => Success([
          for (final text in ['물 주세요', '아파요', '고마워요'])
            HistoryEntry(
              logId: text,
              text: text,
              source: 'preset',
              createdAt: DateTime(2026),
            ),
        ]),
      );
      when(() => playback.state).thenReturn(
        const PlaybackState(text: '물 주세요', status: PlaybackStatus.playing),
      );
      when(() => playback.stream).thenAnswer((_) => const Stream.empty());
      when(playback.start).thenAnswer((_) async {});
      when(playback.close).thenAnswer((_) async {});
      PlaybackRequest? request;
      final router = await tester.pumpApp(
        historyRepository: repository,
        createPlaybackCubit: (value) {
          request = value;
          return playback;
        },
      );
      addTearDown(router.dispose);
      await tester.tap(find.byTooltip('메뉴 열기'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AppDrawer),
          matching: find.text('물 주세요'),
        ),
      );
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/speak/playback');
      expect(request!.origin, PlaybackOrigin.history);
      expect(request!.text, '물 주세요');
      verify(repository.recent).called(1);
      verifyNoMoreInteractions(repository);
    });
  });
}
