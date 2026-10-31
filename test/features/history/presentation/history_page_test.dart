import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/features/history/domain/history.dart';
import 'package:marieum_app/features/history/presentation/history_cubit.dart';
import 'package:marieum_app/features/history/presentation/history_page.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/presentation/cubit/playback_cubit.dart';
import 'package:mocktail/mocktail.dart';
import '../../../helpers/pump_app.dart';

class _MockHistoryCubit extends MockCubit<HistoryState>
    implements HistoryCubit {}

class _MockPlaybackCubit extends MockCubit<PlaybackState>
    implements PlaybackCubit {}

void main() {
  group(HistoryPage, () {
    testWidgets('replays loaded text without another history request', (
      tester,
    ) async {
      final cubit = _MockHistoryCubit();
      final playback = _MockPlaybackCubit();
      final entry = HistoryEntry(
        logId: '1',
        text: '물 주세요',
        source: 'preset',
        createdAt: DateTime(2026),
      );
      when(() => cubit.state).thenReturn(
        HistoryState(status: HistoryStatus.success, entries: [entry], total: 1),
      );
      when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
      when(cubit.load).thenAnswer((_) async {});
      when(cubit.close).thenAnswer((_) async {});
      when(() => playback.state).thenReturn(
        const PlaybackState(text: '물 주세요', status: PlaybackStatus.playing),
      );
      when(() => playback.stream).thenAnswer((_) => const Stream.empty());
      when(playback.start).thenAnswer((_) async {});
      when(playback.close).thenAnswer((_) async {});
      PlaybackRequest? request;
      final router = await tester.pumpApp(
        initialLocation: '/history',
        createHistoryCubit: () => cubit,
        createPlaybackCubit: (value) {
          request = value;
          return playback;
        },
      );
      addTearDown(router.dispose);
      await tester.tap(find.byTooltip('물 주세요 다시 재생'));
      await tester.pumpAndSettle();
      expect(request!.origin, PlaybackOrigin.history);
      expect(request!.text, '물 주세요');
      verify(cubit.load).called(1);
    });
  });
}
