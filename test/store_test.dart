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
      expect(progress!.position, 1);
      expect(progress.total, 2);
      await store.clearRecords();
      expect(await store.count(Scope.all), 2);
      expect(await store.count(Scope.all, pendingOnly: true), 0);
      expect(await store.status(Scope.all, 'old'), isNull);
      expect(await store.isFavorite('old'), isFalse);
      expect(await store.reviewProgress(Scope.all), isNull);
    },
  );
}
