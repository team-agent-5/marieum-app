import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marieum_app/core/error/failure.dart';
import 'package:marieum_app/core/error/result.dart';
import 'package:marieum_app/features/history/domain/history.dart';
import 'package:marieum_app/features/history/presentation/recent_requests.dart';
import 'package:marieum_app/features/speak/domain/entities/playback_request.dart';
import 'package:marieum_app/features/speak/presentation/cubit/playback_cubit.dart';
import 'package:mocktail/mocktail.dart';
import '../../../helpers/pump_app.dart';

class _MockHistory extends Mock implements HistoryRepository {}

class _MockPlayback extends MockCubit<PlaybackState> implements PlaybackCubit {}

void main() {
  group(RecentRequestsCubit, () {
    late _MockHistory repository;
    setUp(() {
      repository = _MockHistory();
    });
    blocTest<RecentRequestsCubit, RecentRequestsState>(
      'loads recent records',
      build: () {
        when(repository.recent).thenAnswer((_) async => const Success([]));
        return RecentRequestsCubit(repository);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const RecentRequestsState(loading: true),
        const RecentRequestsState(),
      ],
    );
    blocTest<RecentRequestsCubit, RecentRequestsState>(
      'exposes an error for retry',
      build: () {
        when(
          repository.recent,
        ).thenAnswer((_) async => const FailureResult(NetworkFailure()));
        return RecentRequestsCubit(repository);
      },
      act: (cubit) => cubit.load(),
      expect: () => [
        const RecentRequestsState(loading: true),
        isA<RecentRequestsState>().having(
          (s) => s.failure,
          'failure',
          isA<NetworkFailure>(),
        ),
      ],
    );
  });
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
        find.descendant(of: find.byType(Drawer), matching: find.text('물 주세요')),
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
