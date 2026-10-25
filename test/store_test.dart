import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:album_cleaner/store.dart';

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
      await store.saveSimilarityHash('photo', '0000000000000000');
      await store.saveSimilarityHash('missing', 'ffffffffffffffff');

      expect((await store.photoRecords()).map((item) => item.id), ['photo']);
      await store.upsertMediaPage([photo], 2);
      await store.finishScan(2);
      expect(await store.similarityHashes(), {'photo': '0000000000000000'});
    },
  );
}
