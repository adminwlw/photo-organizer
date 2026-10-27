import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:album_cleaner/media_repository.dart';
import 'package:album_cleaner/store.dart';

class CountingThumbnailRepository extends MediaRepository {
  int thumbnailRequests = 0;

  @override
  Future<Uint8List?> thumbnail(String id, int width, int height) async {
    thumbnailRequests++;
    return null;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'review marks, undo and local reset affect only review records',
    () async {
      final store = await AppStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);
      const newest = MediaRecord(
        id: 'new',
        takenAt: 2000,
        month: '2026-10',
        type: 1,
        duration: 0,
        screenshot: false,
        selfie: false,
        live: false,
      );
      const older = MediaRecord(
        id: 'old',
        takenAt: 1000,
        month: '2026-10',
        type: 2,
        duration: 5,
        screenshot: false,
        selfie: false,
        live: false,
      );
      await store.upsertMediaPage([newest, older], 1);
      await store.finishScan(1);

      expect(await store.count(Scope.all), 2);
      final counts = await store.mediaCounts();
      expect(counts.total, 2);
      expect(counts.photos, 1);
      expect(counts.videos, 1);
      expect((await store.at(Scope.all, 0))?.id, 'new');
      final change = await store.act(Scope.all, newest, ReviewAction.delete);
      expect(await store.status(Scope.all, 'new'), 'delete');
      expect((await store.queue()).single['media_id'], 'new');
      await store.undo(change!);
      expect(await store.status(Scope.all, 'new'), isNull);
      expect(await store.queue(), isEmpty);

      await store.act(Scope.all, newest, ReviewAction.pending);
      expect(await store.count(Scope.all, pendingOnly: true), 1);
      expect(await store.positionOf(Scope.all, 'new', pendingOnly: true), 0);
      await store.act(Scope.all, older, ReviewAction.keep);
      expect(await store.status(Scope.all, 'old'), 'kept');
      await store.setFavorite('old', true);
      expect(await store.isFavorite('old'), isTrue);
      final progress = await store.reviewProgress(Scope.all);
      expect(progress, isNotNull);
      expect(progress!.position, 0);
      expect(progress.total, 0);
      await store.clearRecords();
      expect(await store.count(Scope.all), 2);
      expect(await store.count(Scope.all, pendingOnly: true), 0);
      expect(await store.status(Scope.all, 'old'), isNull);
      expect(await store.isFavorite('old'), isFalse);
      expect(await store.reviewProgress(Scope.all), isNull);
    },
  );

  test('cached similar count never hashes uncached photos', () async {
    final store = await AppStore.open(path: inMemoryDatabasePath);
    addTearDown(store.close);
    const photos = [
      MediaRecord(
        id: 'a',
        takenAt: 3,
        month: '2026-10',
        type: 1,
        duration: 0,
        screenshot: false,
        selfie: false,
        live: false,
      ),
      MediaRecord(
        id: 'b',
        takenAt: 2,
        month: '2026-10',
        type: 1,
        duration: 0,
        screenshot: false,
        selfie: false,
        live: false,
      ),
      MediaRecord(
        id: 'uncached',
        takenAt: 1,
        month: '2026-10',
        type: 1,
        duration: 0,
        screenshot: false,
        selfie: false,
        live: false,
      ),
    ];
    await store.upsertMediaPage(photos, 1);
    await store.finishScan(1);
    await store.saveSimilarityHash(
      photos[0],
      '0000000000000000',
      algorithmVersion: similarityAlgorithmVersion,
    );
    await store.saveSimilarityHash(
      photos[1],
      '0000000000000001',
      algorithmVersion: similarityAlgorithmVersion,
    );

    expect(await MediaRepository().cachedSimilarPhotoCount(store), 2);
    expect(
      await store.similarityHashes(
        algorithmVersion: similarityAlgorithmVersion,
      ),
      hasLength(2),
    );
  });

  test('similarity hashes expire when media metadata changes', () async {
    final store = await AppStore.open(path: inMemoryDatabasePath);
    addTearDown(store.close);
    const original = MediaRecord(
      id: 'photo',
      takenAt: 1,
      modifiedAt: 10,
      width: 100,
      height: 80,
      month: '2026-10',
      type: 1,
      duration: 0,
      screenshot: false,
      selfie: false,
      live: false,
    );
    await store.upsertMediaPage([original], 1);
    await store.saveSimilarityHash(
      original,
      '0000000000000000',
      algorithmVersion: similarityAlgorithmVersion,
    );

    expect(
      await store.similarityHashes(
        algorithmVersion: similarityAlgorithmVersion,
      ),
      {'photo': '0000000000000000'},
    );

    const edited = MediaRecord(
      id: 'photo',
      takenAt: 1,
      modifiedAt: 11,
      width: 100,
      height: 80,
      month: '2026-10',
      type: 1,
      duration: 0,
      screenshot: false,
      selfie: false,
      live: false,
    );
    await store.upsertMediaPage([edited], 2);

    expect(
      await store.similarityHashes(
        algorithmVersion: similarityAlgorithmVersion,
      ),
      isEmpty,
    );
  });

  test(
    'version 3 databases migrate without keeping unverifiable hashes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'album-cleaner-store-test-',
      );
      final path = '${directory.path}${Platform.pathSeparator}legacy.db';
      final legacy = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await db.execute('''CREATE TABLE media_cache (
            id TEXT PRIMARY KEY, taken_at INTEGER NOT NULL, month TEXT NOT NULL,
            type INTEGER NOT NULL, duration INTEGER NOT NULL,
            screenshot INTEGER NOT NULL, selfie INTEGER NOT NULL,
            live INTEGER NOT NULL, last_seen_at INTEGER NOT NULL)''');
            await db.execute('''CREATE TABLE media_similarity (
            media_id TEXT PRIMARY KEY, hash TEXT NOT NULL)''');
            await db.execute('''CREATE TABLE app_settings (
            key TEXT PRIMARY KEY, value TEXT NOT NULL,
            updated_at INTEGER NOT NULL)''');
          },
        ),
      );
      await legacy.insert('media_cache', {
        'id': 'photo',
        'taken_at': 1,
        'month': '2026-10',
        'type': 1,
        'duration': 0,
        'screenshot': 0,
        'selfie': 0,
        'live': 0,
        'last_seen_at': 1,
      });
      await legacy.insert('media_similarity', {
        'media_id': 'photo',
        'hash': '0000000000000000',
      });
      await legacy.close();

      final store = await AppStore.open(path: path);
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });

      final photo = (await store.photoRecords()).single;
      expect((photo.modifiedAt, photo.width, photo.height), (0, 0, 0));
      expect(
        await store.similarityHashes(
          algorithmVersion: similarityAlgorithmVersion,
        ),
        isEmpty,
      );
      expect(
        await store.similarityGroups(
          algorithmVersion: similarityAlgorithmVersion,
          maxDistance: similarityMaxDistance,
        ),
        isNull,
      );
    },
  );

  test(
    'similarity group snapshots round-trip and prune missing media',
    () async {
      final store = await AppStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);
      final photos = [
        for (var index = 0; index < 3; index++)
          MediaRecord(
            id: 'photo-$index',
            takenAt: 3 - index,
            month: '2026-10',
            type: 1,
            duration: 0,
            screenshot: false,
            selfie: false,
            live: false,
          ),
      ];
      await store.upsertMediaPage(photos, 1);
      await store.finishScan(1);
      await store.replaceSimilarityGroups(
        [
          ['photo-0', 'photo-1'],
        ],
        algorithmVersion: similarityAlgorithmVersion,
        maxDistance: similarityMaxDistance,
      );

      expect(
        await store.similarityGroups(
          algorithmVersion: similarityAlgorithmVersion,
          maxDistance: similarityMaxDistance,
        ),
        [
          ['photo-0', 'photo-1'],
        ],
      );
      expect(
        await store.similarityGeneratedAt(
          algorithmVersion: similarityAlgorithmVersion,
          maxDistance: similarityMaxDistance,
        ),
        isNotNull,
      );
      expect(
        await store.similarityGroups(
          algorithmVersion: similarityAlgorithmVersion + 1,
          maxDistance: similarityMaxDistance,
        ),
        isNull,
      );

      await store.upsertMediaPage([photos[2]], 2);
      await store.finishScan(2);

      expect(
        await store.similarityGroups(
          algorithmVersion: similarityAlgorithmVersion,
          maxDistance: similarityMaxDistance,
        ),
        isEmpty,
      );
      expect(
        await store.similarityGeneratedAt(
          algorithmVersion: similarityAlgorithmVersion,
          maxDistance: similarityMaxDistance,
        ),
        isNull,
      );
    },
  );

  test('similarity scan can stop without replacing a snapshot', () async {
    final store = await AppStore.open(path: inMemoryDatabasePath);
    addTearDown(store.close);
    const photos = [
      MediaRecord(
        id: 'old-group-a',
        takenAt: 2,
        month: '2026-10',
        type: 1,
        duration: 0,
        screenshot: false,
        selfie: false,
        live: false,
      ),
      MediaRecord(
        id: 'old-group-b',
        takenAt: 1,
        month: '2026-10',
        type: 1,
        duration: 0,
        screenshot: false,
        selfie: false,
        live: false,
      ),
    ];
    await store.upsertMediaPage(photos, 1);
    await store.finishScan(1);
    await store.replaceSimilarityGroups(
      [photos.map((photo) => photo.id).toList()],
      algorithmVersion: similarityAlgorithmVersion,
      maxDistance: similarityMaxDistance,
    );

    await expectLater(
      () => MediaRepository().findSimilarPhotos(
        store,
        (_, _) {},
        shouldCancel: () => true,
      ),
      throwsA(isA<SimilarityScanCancelled>()),
    );
    expect(
      await store.similarityGroups(
        algorithmVersion: similarityAlgorithmVersion,
        maxDistance: similarityMaxDistance,
      ),
      [photos.map((photo) => photo.id).toList()],
    );
  });

  test('a valid group snapshot opens without reading thumbnails', () async {
    final store = await AppStore.open(path: inMemoryDatabasePath);
    addTearDown(store.close);
    final photos = [
      for (var index = 0; index < 2; index++)
        MediaRecord(
          id: 'photo-$index',
          takenAt: 2 - index,
          modifiedAt: 10,
          width: 100,
          height: 80,
          month: '2026-10',
          type: 1,
          duration: 0,
          screenshot: false,
          selfie: false,
          live: false,
        ),
    ];
    await store.upsertMediaPage(photos, 1);
    await store.finishScan(1);
    for (final photo in photos) {
      await store.saveSimilarityHash(
        photo,
        photo.id == 'photo-0' ? '0000000000000000' : '0000000000000001',
        algorithmVersion: similarityAlgorithmVersion,
      );
    }
    await store.replaceSimilarityGroups(
      [
        ['photo-0', 'photo-1'],
      ],
      algorithmVersion: similarityAlgorithmVersion,
      maxDistance: similarityMaxDistance,
    );
    final repository = CountingThumbnailRepository();

    final groups = await repository.findSimilarPhotos(store, (_, _) {});

    expect(groups.single.items.map((item) => item.id), ['photo-0', 'photo-1']);
    expect(repository.thumbnailRequests, 0);
  });

  test('deleting a pending item removes it from the pending list', () async {
    final store = await AppStore.open(path: inMemoryDatabasePath);
    addTearDown(store.close);
    final items = List.generate(
      38,
      (index) => MediaRecord(
        id: 'photo-$index',
        takenAt: 1000 - index,
        month: '2026-10',
        type: 1,
        duration: 0,
        screenshot: false,
        selfie: false,
        live: false,
      ),
    );
    await store.upsertMediaPage(items, 1);
    await store.finishScan(1);
    for (final item in items) {
      await store.act(Scope.all, item, ReviewAction.pending);
    }

    expect(await store.count(Scope.all, pendingOnly: true), 38);
    final removed = await store.at(Scope.all, 0, pendingOnly: true);
    await store.act(Scope.all, removed!, ReviewAction.delete);

    expect(await store.count(Scope.all, pendingOnly: true), 37);
    expect(
      (await store.at(Scope.all, 0, pendingOnly: true))?.id,
      isNot(removed.id),
    );
  });

  test('queued media is hidden from the regular media list', () async {
    final store = await AppStore.open(path: inMemoryDatabasePath);
    addTearDown(store.close);
    const queued = MediaRecord(
      id: 'queued',
      takenAt: 2000,
      month: '2026-10',
      type: 1,
      duration: 0,
      screenshot: false,
      selfie: false,
      live: false,
    );
    const remaining = MediaRecord(
      id: 'remaining',
      takenAt: 1000,
      month: '2026-10',
      type: 1,
      duration: 0,
      screenshot: false,
      selfie: false,
      live: false,
    );
    await store.upsertMediaPage([queued, remaining], 1);
    await store.finishScan(1);

    await store.act(Scope.all, queued, ReviewAction.delete);

    expect(await store.count(Scope.all), 1);
    expect((await store.list(Scope.all)).map((item) => item.id), ['remaining']);
    expect((await store.queue()).single['media_id'], 'queued');
  });

  test(
    'restoring a pending item returns it to all media and can be undone',
    () async {
      final store = await AppStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);
      const item = MediaRecord(
        id: 'pending',
        takenAt: 1000,
        month: '2026-10',
        type: 1,
        duration: 0,
        screenshot: false,
        selfie: false,
        live: false,
      );
      await store.upsertMediaPage([item], 1);
      await store.finishScan(1);
      await store.act(Scope.all, item, ReviewAction.pending);

      final restored = await store.act(Scope.all, item, ReviewAction.restore);
      expect(await store.count(Scope.all, pendingOnly: true), 0);
      expect(await store.count(Scope.all, unreviewedOnly: true), 1);

      await store.undo(restored!);
      expect(await store.count(Scope.all, pendingOnly: true), 1);
    },
  );

  test('year scope includes every month in that year only', () async {
    final store = await AppStore.open(path: inMemoryDatabasePath);
    addTearDown(store.close);
    final items =
        [
              ('october', 3000, '2026-10'),
              ('january', 2000, '2026-01'),
              ('previous-year', 1000, '2025-12'),
            ]
            .map(
              (item) => MediaRecord(
                id: item.$1,
                takenAt: item.$2,
                month: item.$3,
                type: 1,
                duration: 0,
                screenshot: false,
                selfie: false,
                live: false,
              ),
            )
            .toList();
    await store.upsertMediaPage(items, 1);
    await store.finishScan(1);

    expect(await store.count(Scope.year('2026')), 2);
    expect((await store.at(Scope.year('2026'), 0))?.id, 'october');
    expect((await store.at(Scope.year('2026'), 1))?.id, 'january');
  });

  test(
    'reviewing 38 items removes each decision from the active list',
    () async {
      final store = await AppStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);
      final items = List.generate(
        38,
        (index) => MediaRecord(
          id: 'review-$index',
          takenAt: 2000 - index,
          month: '2026-10',
          type: 1,
          duration: 0,
          screenshot: false,
          selfie: false,
          live: false,
        ),
      );
      await store.upsertMediaPage(items, 1);
      await store.finishScan(1);
      final seen = <String>{};

      for (var remaining = 38; remaining > 0; remaining--) {
        final current = await store.at(Scope.all, 0, unreviewedOnly: true);
        expect(current, isNotNull);
        expect(seen.add(current!.id), isTrue);
        await store.act(Scope.all, current, ReviewAction.pending);
        expect(
          await store.count(Scope.all, unreviewedOnly: true),
          remaining - 1,
        );
      }

      expect(seen, hasLength(38));
      expect(await store.at(Scope.all, 0, unreviewedOnly: true), isNull);
      expect(await store.count(Scope.all, pendingOnly: true), 38);
    },
  );

  test(
    'photo records and similarity hashes stay aligned after a scan',
    () async {
      final store = await AppStore.open(path: inMemoryDatabasePath);
      addTearDown(store.close);
      const photo = MediaRecord(
        id: 'photo',
        takenAt: 2000,
        month: '2026-10',
        type: 1,
        duration: 0,
        screenshot: false,
        selfie: false,
        live: false,
      );
      const video = MediaRecord(
        id: 'video',
        takenAt: 1000,
        month: '2026-10',
        type: 2,
        duration: 10,
        screenshot: false,
        selfie: false,
        live: false,
      );
      await store.upsertMediaPage([photo, video], 1);
      await store.saveSimilarityHash(
        photo,
        '0000000000000000',
        algorithmVersion: similarityAlgorithmVersion,
      );
      await store.saveSimilarityHash(
        const MediaRecord(
          id: 'missing',
          takenAt: 0,
          month: '2026-10',
          type: 1,
          duration: 0,
          screenshot: false,
          selfie: false,
          live: false,
        ),
        'ffffffffffffffff',
        algorithmVersion: similarityAlgorithmVersion,
      );

      expect((await store.photoRecords()).map((item) => item.id), ['photo']);
      await store.upsertMediaPage([photo], 2);
      await store.finishScan(2);
      expect(
        await store.similarityHashes(
          algorithmVersion: similarityAlgorithmVersion,
        ),
        {'photo': '0000000000000000'},
      );
    },
  );
}
