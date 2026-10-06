import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/network/api_exception.dart';
import 'package:mconnect/core/network/platform_http.dart';
import 'package:mconnect/features/download/domain/entities/download_failure.dart';
import 'package:mconnect/features/download/domain/entities/download_task.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

void main() {
  group('typed ApiExceptions map to download failures', () {
    final cases = <ApiException, DownloadFailureKind>{
      NetworkException(): DownloadFailureKind.network,
      LoginExpiredException(): DownloadFailureKind.auth,
      NoVipMembershipException('网易云'): DownloadFailureKind.vip,
      StorageFullException(): DownloadFailureKind.disk,
      NotFoundException(): DownloadFailureKind.notFound,
      LyricsNotFoundException(): DownloadFailureKind.notFound,
      UnsupportedActionException('酷狗'): DownloadFailureKind.unsupported,
      StoragePermissionDeniedException(): DownloadFailureKind.storagePermission,
      RequestCancelledException(): DownloadFailureKind.cancelled,
    };

    cases.forEach((error, expected) {
      test('${error.runtimeType} -> ${expected.name}', () {
        final failure = DownloadFailure.from(error);
        expect(failure.kind, expected);
        expect(failure.message, isNotEmpty);
      });
    });

    test('an unclassifiable error is unknown, and unknown is not retryable',
        () {
      final failure = DownloadFailure.from(StateError('boom'));
      expect(failure.kind, DownloadFailureKind.unknown);
      expect(failure.isRetryable, isFalse);
    });

    test('a DioException carrying a translated exception is unwrapped', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.badResponse,
        response: Response<void>(requestOptions: RequestOptions(path: '/x'), statusCode: 401),
      );
      expect(
        DownloadFailure.from(dioError).kind,
        DownloadFailureKind.auth,
        reason: 'apiExceptionOf unwraps the PlatformErrorInterceptor result',
      );
      expect(translateDioException(dioError), isA<LoginExpiredException>());
    });
  });

  group('HTTP status mapping', () {
    test('401/403 need a new login', () {
      expect(
        DownloadFailure.fromStatus(403).kind,
        DownloadFailureKind.auth,
      );
    });

    test('404/410 mean the track is gone', () {
      expect(
        DownloadFailure.fromStatus(404).kind,
        DownloadFailureKind.notFound,
      );
    });

    test('a bad Range is a network retry, not a dead end', () {
      expect(
        DownloadFailure.fromStatus(416).kind,
        DownloadFailureKind.network,
      );
    });

    test('500 is reported with its status code', () {
      final failure = DownloadFailure.fromStatus(500);
      expect(failure.kind, DownloadFailureKind.unsupported);
      expect(failure.message, contains('500'));
    });
  });

  test('network and disk failures are the retryable kinds', () {
    expect(DownloadFailure.network().isRetryable, isTrue);
    expect(DownloadFailure.storageFull().isRetryable, isTrue);
    expect(DownloadFailure.cancelled().isRetryable, isFalse);
    expect(
      const DownloadFailure(
        kind: DownloadFailureKind.auth,
        message: 'x',
      ).isRetryable,
      isFalse,
    );
  });

  test('the failure kind survives a JSON round-trip', () {
    final task = DownloadTask(
      id: 'netease_s1_low',
      song: const Song(
        id: 's1',
        platform: PlatformType.netease,
        name: 'Song 1',
        artists: [Artist(id: 'a1', name: 'Artist 1')],
      ),
      quality: AudioLevel.low,
      status: DownloadStatus.failed,
      error: '网络连接失败，请检查网络后重试',
      failureKind: DownloadFailureKind.network,
      createdAt: DateTime(2026, 5, 29),
      lastAccessedAt: DateTime(2026, 5, 30),
    );

    final restored = DownloadTask.fromJson(task.toJson());

    expect(restored!.failureKind, DownloadFailureKind.network);
    expect(restored.lastAccessedAt, DateTime(2026, 5, 30));
  });

  test('an absent failure kind restores as null (older persisted rows)', () {
    final task = DownloadTask(
      id: 'netease_s1_low',
      song: const Song(
        id: 's1',
        platform: PlatformType.netease,
        name: 'Song 1',
        artists: [Artist(id: 'a1', name: 'Artist 1')],
      ),
      quality: AudioLevel.low,
      createdAt: DateTime(2026, 5, 29),
    );
    final json = task.toJson()..remove('failureKind');

    expect(DownloadTask.fromJson(json)!.failureKind, isNull);
  });

  test('cache and manual task ids differ', () {
    const song = Song(
      id: 's1',
      platform: PlatformType.qq,
      name: 'Song 1',
      artists: [Artist(id: 'a1', name: 'Artist 1')],
    );

    expect(DownloadTask.buildId(song, AudioLevel.low), 'qq_s1_low');
    expect(
      DownloadTask.buildCacheId(song, AudioLevel.low),
      'qq_s1_low_cache',
      reason: 'sharing one id is what made manual download impossible',
    );
  });

  test('cache recency falls back from access to completion to creation', () {
    final created = DateTime(2026, 1, 1);
    final completed = DateTime(2026, 2, 1);
    final accessed = DateTime(2026, 3, 1);
    const song = Song(
      id: 's1',
      platform: PlatformType.netease,
      name: 'Song 1',
      artists: [Artist(id: 'a1', name: 'Artist 1')],
    );
    DownloadTask task({DateTime? completedAt, DateTime? lastAccessedAt}) =>
        DownloadTask(
          id: 'x',
          song: song,
          quality: AudioLevel.low,
          createdAt: created,
          completedAt: completedAt,
          lastAccessedAt: lastAccessedAt,
        );

    expect(task().cacheRecency, created);
    expect(task(completedAt: completed).cacheRecency, completed);
    expect(
      task(completedAt: completed, lastAccessedAt: accessed).cacheRecency,
      accessed,
    );
  });
}
