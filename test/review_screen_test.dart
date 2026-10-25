import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:album_cleaner/main.dart';
import 'package:album_cleaner/media_repository.dart';
import 'package:album_cleaner/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeMediaRepository extends MediaRepository {
  int videoFileRequests = 0;

  @override
  Future<List<SystemAlbumSummary>> systemAlbums() async => const [];

  @override
  Future<List<SystemCategorySummary>> systemCategories() async => const [];

  @override
  Future<Uint8List?> thumbnail(String id, int width, int height) async => null;

  @override
  Future<File?> videoFile(String id) async {
    videoFileRequests++;
    return null;
  }
}

class AlbumsMediaRepository extends FakeMediaRepository {
  @override
  Future<List<SystemAlbumSummary>> systemAlbums() async => [
    for (final name in ['Camera', 'QQ', 'Download'])
      SystemAlbumSummary(
        path: AssetPathEntity(id: name.toLowerCase(), name: name),
        count: 1,
        coverId: null,
        group: SystemAlbumGroup.album,
      ),
  ];
}

class FakeAppStore extends AppStore {
  FakeAppStore(super.db, {this.queueCount = 0});

  final int queueCount;
  final Set<String> favorites = {};

  @override
  Future<String?> anchor(Scope scope) async => null;

  @override
  Future<List<Map<String, Object?>>> queue() async =>
      List.generate(queueCount, (index) => {'media_id': 'queued-$index'});

  @override
  Future<void> saveAnchor(Scope scope, MediaRecord media) async {}

  @override
  Future<bool> isFavorite(String id) async => favorites.contains(id);

  @override
  Future<void> setFavorite(String id, bool favorite) async {
    favorite ? favorites.add(id) : favorites.remove(id);
  }
}

class UndoAppStore extends FakeAppStore {
  UndoAppStore(super.db);

  int queued = 0;
  final List<String> undone = [];
  final List<ReviewAction> actions = [];

  @override
  Future<List<Map<String, Object?>>> queue() async =>
      List.generate(queued, (index) => {'media_id': 'queued-$index'});

  @override
  Future<ActionSnapshot?> act(
    Scope scope,
    MediaRecord media,
    ReviewAction action,
  ) async {
    actions.add(action);
    if (action == ReviewAction.delete) queued++;
    return ActionSnapshot(media.id, scope.key, null, null, const [], null);
  }

  @override
  Future<void> undo(ActionSnapshot snapshot) async {
    queued--;
    undone.add(snapshot.mediaId);
  }
}

class DelayedActionStore extends UndoAppStore {
  DelayedActionStore(super.db);

  final actionResult = Completer<ActionSnapshot?>();

  @override
  Future<ActionSnapshot?> act(
    Scope scope,
    MediaRecord media,
    ReviewAction action,
  ) => actionResult.future;
}

class ScopeAppStore extends UndoAppStore {
  ScopeAppStore(super.db);

  static const items = [photo, nextPhoto];

  @override
  Future<ReviewProgress?> reviewProgress(Scope scope) async => null;

  @override
  Future<int> count(Scope scope, {bool pendingOnly = false}) async =>
      items.length;

  @override
  Future<MediaRecord?> at(
    Scope scope,
    int index, {
    bool pendingOnly = false,
  }) async => index >= 0 && index < items.length ? items[index] : null;

  @override
  Future<int> positionOf(
    Scope scope,
    String mediaId, {
    bool pendingOnly = false,
  }) async => items.indexWhere((item) => item.id == mediaId);
}

class ProgressScopeAppStore extends ScopeAppStore {
  ProgressScopeAppStore(super.db);

  @override
  Future<ReviewProgress?> reviewProgress(Scope scope) async =>
      const ReviewProgress(position: 1, total: 2, updatedAt: 1000);
}

class LongScopeAppStore extends ScopeAppStore {
  LongScopeAppStore(super.db, {required this.initialAnchor});

  final String initialAnchor;
  final items = List.generate(
    100,
    (index) => MediaRecord(
      id: 'photo-$index',
      takenAt: 100000 - index,
      month: '2026-10',
      type: 1,
      duration: 0,
      screenshot: false,
      selfie: false,
      live: false,
    ),
  );

  @override
  Future<String?> anchor(Scope scope) async => initialAnchor;

  @override
  Future<int> count(Scope scope, {bool pendingOnly = false}) async =>
      items.length;

  @override
  Future<MediaRecord?> at(
    Scope scope,
    int index, {
    bool pendingOnly = false,
  }) async => index >= 0 && index < items.length ? items[index] : null;

  @override
  Future<int> positionOf(
    Scope scope,
    String mediaId, {
    bool pendingOnly = false,
  }) async => items.indexWhere((item) => item.id == mediaId);
}

class QueueAppStore extends FakeAppStore {
  QueueAppStore(super.db, Iterable<String> ids) : ids = ids.toList();

  final List<String> ids;

  @override
  Future<List<Map<String, Object?>>> queue() async => ids
      .map((id) => <String, Object?>{'media_id': id, 'status': 'queued'})
      .toList();

  @override
  Future<void> removeFromQueue(String id) async {
    ids.remove(id);
  }
}

const photo = MediaRecord(
  id: 'photo',
  takenAt: 1000,
  month: '2026-10',
  type: 1,
  duration: 0,
  screenshot: false,
  selfie: false,
  live: false,
);

const nextPhoto = MediaRecord(
  id: 'next-photo',
  takenAt: 900,
  month: '2026-10',
  type: 1,
  duration: 0,
  screenshot: false,
  selfie: false,
  live: false,
);

const thirdPhoto = MediaRecord(
  id: 'third-photo',
  takenAt: 800,
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
  duration: 8,
  screenshot: false,
  selfie: false,
  live: false,
);

void main() {
  late Database database;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    database = await databaseFactory.openDatabase(inMemoryDatabasePath);
  });

  tearDownAll(() => database.close());

  testWidgets('the active video preview starts playback automatically', (
    tester,
  ) async {
    final media = FakeMediaRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MediaView(media, video, autoplay: true)),
      ),
    );
    await tester.pump();

    expect(media.videoFileRequests, 1);
  });

  testWidgets('a preloaded neighboring video stays paused', (tester) async {
    final media = FakeMediaRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MediaView(media, video, autoplay: false)),
      ),
    );
    await tester.pump();

    expect(media.videoFileRequests, 0);
  });

  testWidgets('the review queue count stays fully inside the viewport', (
    tester,
  ) async {
    final store = FakeAppStore(database, queueCount: 123);

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          CleanerState(store, FakeMediaRepository()),
          Scope.all,
          source: const [photo],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final badge = find.byKey(const Key('queue-count-badge'));
    expect(badge, findsOneWidget);
    expect(tester.getSize(badge).width, greaterThan(22));
    expect(tester.getTopLeft(badge).dx, greaterThanOrEqualTo(0));
    expect(
      tester.getTopRight(badge).dx,
      lessThanOrEqualTo(
        tester.view.physicalSize.width / tester.view.devicePixelRatio,
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the next item grows and fades in from the center', (
    tester,
  ) async {
    final store = FakeAppStore(database);

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          CleanerState(store, FakeMediaRepository()),
          Scope.all,
          source: const [photo, nextPhoto],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final currentMedia = find.byKey(const ValueKey('photo'));
    final gesture = await tester.startGesture(tester.getCenter(currentMedia));
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();

    final opacity = tester.widget<Opacity>(
      find.byKey(const Key('incoming-media-opacity')),
    );
    final scale = tester.widget<Transform>(
      find.byKey(const Key('incoming-media-scale')),
    );
    expect(opacity.opacity, inExclusiveRange(0, 1));
    expect(scale.transform.storage[0], inExclusiveRange(0.86, 1));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an upward swipe highlights the delete control', (tester) async {
    final store = FakeAppStore(database, queueCount: 7);

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          CleanerState(store, FakeMediaRepository()),
          Scope.all,
          source: const [photo],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('photo'))),
    );
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();

    final control = tester.widget<Transform>(
      find.byKey(const Key('delete-control-scale')),
    );
    expect(control.transform.storage[0], greaterThan(1));
    expect(find.text('已加入待删除'), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a swipe locks to one axis for the whole gesture', (
    tester,
  ) async {
    final store = FakeAppStore(database);

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          CleanerState(store, FakeMediaRepository()),
          Scope.all,
          source: const [photo, nextPhoto],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    var gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('photo'))),
    );
    await gesture.moveBy(const Offset(-60, -35));
    await tester.pump();
    var translation = tester.widget<Transform>(
      find.byKey(const Key('media-drag-translation')),
    );
    expect(translation.transform.storage[12], lessThan(0));
    expect(translation.transform.storage[13], 0);
    await gesture.up();
    await tester.pumpAndSettle();

    gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('photo'))),
    );
    await gesture.moveBy(const Offset(35, -60));
    await tester.pump();
    translation = tester.widget<Transform>(
      find.byKey(const Key('media-drag-translation')),
    );
    expect(translation.transform.storage[12], 0);
    expect(translation.transform.storage[13], lessThan(0));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('deleting shrinks the media toward the top-right control', (
    tester,
  ) async {
    final store = UndoAppStore(database);

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          CleanerState(store, FakeMediaRepository()),
          Scope.all,
          source: const [photo, nextPhoto],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('photo'))),
    );
    await gesture.moveBy(const Offset(25, -100));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));

    final scale = tester.widget<Transform>(
      find.byKey(const Key('action-media-scale')),
    );
    final translation = tester.widget<Transform>(
      find.byKey(const Key('media-drag-translation')),
    );
    expect(scale.transform.storage[0], lessThan(1));
    expect(translation.transform.storage[12], greaterThan(0));
    expect(translation.transform.storage[13], lessThan(0));

    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('undo can restore multiple actions in reverse order', (
    tester,
  ) async {
    final store = UndoAppStore(database);

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          CleanerState(store, FakeMediaRepository()),
          Scope.all,
          source: const [photo, nextPhoto],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    for (final id in ['photo', 'next-photo']) {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey(id))),
      );
      await gesture.moveBy(const Offset(0, -100));
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(store.queued, 2);
    await tester.tap(find.byKey(const Key('undo-control')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('next-photo')), findsOneWidget);

    await tester.tap(find.byKey(const Key('undo-control')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo')), findsOneWidget);
    expect(store.undone, ['next-photo', 'photo']);
    expect(store.queued, 0);
    final undoButton = tester.widget<IconButton>(
      find.byKey(const Key('undo-control')),
    );
    expect(undoButton.onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an action finishes without an extra post-animation pause', (
    tester,
  ) async {
    final store = UndoAppStore(database);

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          CleanerState(store, FakeMediaRepository()),
          Scope.all,
          source: const [photo, nextPhoto],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('photo'))),
    );
    await gesture.moveBy(const Offset(0, -100));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pump();

    final undoButton = tester.widget<IconButton>(
      find.byKey(const Key('undo-control')),
    );
    expect(undoButton.onPressed, isNotNull);
    expect(find.byKey(const ValueKey('next-photo')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an action animation starts before persistence finishes', (
    tester,
  ) async {
    final store = DelayedActionStore(database);

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          CleanerState(store, FakeMediaRepository()),
          Scope.all,
          source: const [photo, nextPhoto],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('photo'))),
    );
    await gesture.moveBy(const Offset(0, -100));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final translation = tester.widget<Transform>(
      find.byKey(const Key('media-drag-translation')),
    );
    expect(translation.transform.storage[13], lessThan(-100));

    store.actionResult.complete(null);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a gradual vertical action always advances to the next item', (
    tester,
  ) async {
    final store = UndoAppStore(database);

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          CleanerState(store, FakeMediaRepository()),
          Scope.all,
          initialIndex: 1,
          source: const [photo, nextPhoto, thirdPhoto],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('next-photo'))),
    );
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    final dragged = tester.widget<Transform>(
      find.byKey(const Key('media-drag-translation')),
    );
    expect(dragged.transform.storage[13], lessThanOrEqualTo(-100));
    await gesture.up();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(store.actions, [ReviewAction.delete]);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('third-photo')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('favorite toggles and stays in the local store', (tester) async {
    final store = FakeAppStore(database);

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          CleanerState(store, FakeMediaRepository()),
          Scope.all,
          source: const [photo],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const Key('favorite-control')));
    await tester.pump();
    expect(store.favorites, contains('photo'));
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the main review defaults a downward swipe to return to album', (
    tester,
  ) async {
    final store = UndoAppStore(database);
    final app = CleanerState(store, FakeMediaRepository());
    expect(app.downAction, DownSwipeAction.returnToAlbum);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open-review'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ReviewScreen(
                    app,
                    Scope.all,
                    source: const [photo, nextPhoto],
                  ),
                ),
              ),
              child: const Text('打开整理'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-review')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('photo'))),
    );
    await gesture.moveBy(const Offset(0, 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(ReviewScreen), findsNothing);
    expect(store.actions, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('continue review returns down to the all-media grid', (
    tester,
  ) async {
    final store = ScopeAppStore(database);
    final app = CleanerState(store, FakeMediaRepository());

    await tester.pumpWidget(
      MaterialApp(home: ScopeScreen(app, Scope.all, startReview: true)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ReviewScreen), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('photo'))),
    );
    await gesture.moveBy(const Offset(0, 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(ReviewScreen), findsNothing);
    expect(find.byType(ScopeScreen), findsOneWidget);
    expect(find.text('全部照片与视频'), findsOneWidget);
    expect(store.actions, isEmpty);
  });

  testWidgets('returning from review locates the current item in the grid', (
    tester,
  ) async {
    final store = LongScopeAppStore(database, initialAnchor: 'photo-80');
    final app = CleanerState(store, FakeMediaRepository());

    await tester.pumpWidget(
      MaterialApp(home: ScopeScreen(app, Scope.all, startReview: true)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo-80')), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('photo-80'))),
    );
    await gesture.moveBy(const Offset(0, 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(ReviewScreen), findsNothing);
    expect(find.byKey(const Key('focused-scope-item-80')), findsOneWidget);
  });

  testWidgets('acting on the last item keeps backward browsing available', (
    tester,
  ) async {
    final store = UndoAppStore(database);

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          CleanerState(store, FakeMediaRepository()),
          Scope.all,
          initialIndex: 1,
          source: const [photo, nextPhoto],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    var gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('next-photo'))),
    );
    await gesture.moveBy(const Offset(0, -100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('next-photo')), findsOneWidget);
    expect(find.text('本范围已整理完成'), findsNothing);

    gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('next-photo'))),
    );
    await gesture.moveBy(const Offset(-100, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('已经是最后一张，可以向右滑动返回上一张'), findsOneWidget);

    gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('next-photo'))),
    );
    await gesture.moveBy(const Offset(100, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo')), findsOneWidget);
  });

  testWidgets('home categories include all media and albums use a grid', (
    tester,
  ) async {
    final app = CleanerState(ScopeAppStore(database), AlbumsMediaRepository());

    await tester.pumpWidget(MaterialApp(home: HomeScreen(app)));
    await tester.pumpAndSettle();
    expect(find.text('全部照片与视频'), findsOneWidget);

    await tester.tap(find.text('相册'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('system-album-grid')), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('QQ'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('year-month cards show month and count without repeating year', (
    tester,
  ) async {
    final app = CleanerState(ScopeAppStore(database), FakeMediaRepository());
    app.months = [('2026-10', 3), ('2026-09', 2)];

    await tester.pumpWidget(MaterialApp(home: HomeScreen(app)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('相册'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('年月'));
    await tester.pumpAndSettle();

    expect(find.text('2026'), findsOneWidget);
    expect(find.text('10月'), findsOneWidget);
    expect(find.text('3 项'), findsOneWidget);
    expect(find.text('2026-10'), findsNothing);
    final monthPosition = tester.getTopLeft(find.text('10月'));
    final countPosition = tester.getTopLeft(find.text('3 项'));
    expect(monthPosition.dx, lessThan(countPosition.dx));
    expect(monthPosition.dy, lessThan(countPosition.dy));
    expect(tester.widget<Text>(find.text('10月')).style?.shadows, isNotEmpty);
    expect(tester.widget<Text>(find.text('3 项')).style?.shadows, isNotEmpty);
  });

  testWidgets('home keeps one resume entry and the media grid has none', (
    tester,
  ) async {
    final app = CleanerState(
      ProgressScopeAppStore(database),
      AlbumsMediaRepository(),
    );

    await tester.pumpWidget(MaterialApp(home: HomeScreen(app)));
    await tester.pumpAndSettle();
    expect(find.text('继续整理'), findsOneWidget);
    expect(find.text('回到上次位置'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('review-hero'))).height,
      lessThanOrEqualTo(140),
    );

    await tester.pumpWidget(MaterialApp(home: ScopeScreen(app, Scope.all)));
    await tester.pumpAndSettle();
    expect(find.text('继续整理'), findsNothing);
  });

  testWidgets('the delete queue uses four columns and restores selections', (
    tester,
  ) async {
    final store = QueueAppStore(database, ['photo', 'next-photo']);

    await tester.pumpWidget(
      MaterialApp(
        home: QueueScreen(CleanerState(store, FakeMediaRepository())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 4);
    expect(find.text('恢复 0 项'), findsOneWidget);
    expect(find.text('删除 0 项'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('恢复 1 项'), findsOneWidget);
    expect(find.text('删除 1 项'), findsOneWidget);

    await tester.tap(find.text('恢复 1 项'));
    await tester.pumpAndSettle();
    expect(store.ids, ['next-photo']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('queue preview is fullscreen and supports four-times zoom', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: QueuePreviewScreen(FakeMediaRepository(), photo)),
    );

    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const Key('queue-preview-zoom')),
    );
    expect(viewer.maxScale, 4);
    expect(find.text('全屏预览'), findsOneWidget);
  });
}
