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
  int livePhotoFileRequests = 0;

  @override
  bool get supportsLivePhotoPlayback => true;

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

  @override
  Future<File?> livePhotoVideoFile(String id) async {
    livePhotoFileRequests++;
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

class SimilarMediaRepository extends FakeMediaRepository {
  @override
  Future<List<SimilarPhotoGroup>> findSimilarPhotos(
    AppStore store,
    void Function(int, int) onProgress,
  ) async {
    onProgress(2, 2);
    return const [
      SimilarPhotoGroup([photo, nextPhoto]),
    ];
  }
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
  Future<Set<String>> reviewedIds(Scope scope) async => const {};

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
  Future<int> count(
    Scope scope, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async => items.length;

  @override
  Future<MediaRecord?> at(
    Scope scope,
    int index, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async => index >= 0 && index < items.length ? items[index] : null;

  @override
  Future<List<MediaRecord>> list(
    Scope scope, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async => items;

  @override
  Future<int> positionOf(
    Scope scope,
    String mediaId, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
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
  Future<int> count(
    Scope scope, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async => items.length;

  @override
  Future<MediaRecord?> at(
    Scope scope,
    int index, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async => index >= 0 && index < items.length ? items[index] : null;

  @override
  Future<List<MediaRecord>> list(
    Scope scope, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async => items;

  @override
  Future<int> positionOf(
    Scope scope,
    String mediaId, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async => items.indexWhere((item) => item.id == mediaId);
}

class VideoScopeAppStore extends ScopeAppStore {
  VideoScopeAppStore(super.db);

  @override
  Future<int> count(
    Scope scope, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async => 1;

  @override
  Future<MediaRecord?> at(
    Scope scope,
    int index, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async => index == 0 ? video : null;

  @override
  Future<List<MediaRecord>> list(
    Scope scope, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async => const [video];
}

class ReviewedVideoScopeAppStore extends ScopeAppStore {
  ReviewedVideoScopeAppStore(super.db);

  static const allItems = [photo, video, nextPhoto];
  static const unreviewedItems = [photo, nextPhoto];

  @override
  Future<int> count(
    Scope scope, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async => unreviewedOnly ? unreviewedItems.length : allItems.length;

  @override
  Future<MediaRecord?> at(
    Scope scope,
    int index, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async {
    final items = unreviewedOnly ? unreviewedItems : allItems;
    return index >= 0 && index < items.length ? items[index] : null;
  }

  @override
  Future<List<MediaRecord>> list(
    Scope scope, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async => unreviewedOnly ? unreviewedItems : allItems;

  @override
  Future<int> positionOf(
    Scope scope,
    String mediaId, {
    bool pendingOnly = false,
    bool unreviewedOnly = false,
  }) async {
    if (unreviewedOnly && mediaId == video.id) return 1;
    final items = unreviewedOnly ? unreviewedItems : allItems;
    return items.indexWhere((item) => item.id == mediaId);
  }
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

  @override
  Future<List<(String, int)>> months() async => const [];
}

class DeletingMediaRepository extends FakeMediaRepository {
  @override
  Future<PermissionState> permission() async => PermissionState.authorized;

  @override
  Future<void> scan(AppStore store, void Function(int) onProgress) async {}

  @override
  Future<bool> usesRecoverableTrash() async => false;

  @override
  Future<Map<String, int>> mediaSizes(Iterable<String> ids) async => {
    for (final id in ids) id: 2 * 1024 * 1024,
  };

  @override
  Future<Map<String, String>> deleteReviewedMedia(
    AppStore store,
    List<String> ids,
  ) async {
    for (final id in ids) {
      await store.removeFromQueue(id);
    }
    return {for (final id in ids) id: 'confirmedRemoved'};
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

const livePhoto = MediaRecord(
  id: 'live-photo',
  takenAt: 1000,
  month: '2026-10',
  type: 1,
  duration: 0,
  screenshot: false,
  selfie: false,
  live: true,
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

  testWidgets('a live photo requests its motion clip while held', (
    tester,
  ) async {
    final media = FakeMediaRepository();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: MediaView(media, livePhoto))),
    );
    await tester.longPress(find.byKey(const Key('live-photo-hold-target')));
    await tester.pump();

    expect(media.livePhotoFileRequests, 1);
  });

  test('system category labels follow the requested language', () {
    expect(
      systemCategoryLabel(
        SystemCategoryKind.favorites,
        providerLabel: 'Favorites',
        languageCode: 'zh',
      ),
      '个人收藏',
    );
    expect(
      systemCategoryLabel(
        SystemCategoryKind.favorites,
        providerLabel: 'Favorites',
        languageCode: 'en',
      ),
      'Favorites',
    );
  });

  testWidgets('review shows only a shadowed media surface above controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          CleanerState(FakeAppStore(database), FakeMediaRepository()),
          Scope.videos,
          source: const [video],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('media-edge-blur')), findsNothing);
    final surface = tester.widget<DecoratedBox>(
      find.byKey(const Key('media-surface-shadow')),
    );
    final shadows = (surface.decoration as BoxDecoration).boxShadow!;
    expect(shadows, isNotEmpty);
    expect(shadows.single.color, const Color(0x3D000000));
    final progressPosition = tester
        .widgetList<Positioned>(
          find.ancestor(
            of: find.byType(LinearProgressIndicator),
            matching: find.byType(Positioned),
          ),
        )
        .firstWhere((positioned) => positioned.left == 18);
    expect(progressPosition.bottom, 18);
    await tester.pumpWidget(const SizedBox.shrink());
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

  testWidgets('the next item follows the gesture in from the screen edge', (
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

    final translation = tester.widget<Transform>(
      find.byKey(const Key('incoming-media-translation')),
    );
    expect(translation.transform.storage[12], greaterThan(0));
    expect(
      translation.transform.storage[12],
      lessThan(tester.view.physicalSize.width / tester.view.devicePixelRatio),
    );
    final currentTransforms = tester.widgetList<Transform>(
      find.ancestor(of: currentMedia, matching: find.byType(Transform)),
    );
    expect(
      currentTransforms.every(
        (transform) =>
            transform.transform.storage[1].abs() < 0.000001 &&
            transform.transform.storage[4].abs() < 0.000001,
      ),
      isTrue,
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a short fast horizontal flick advances to the next item', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          CleanerState(FakeAppStore(database), FakeMediaRepository()),
          Scope.all,
          source: const [photo, nextPhoto],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.fling(
      find.byKey(const Key('review-gesture')),
      const Offset(-48, 0),
      1400,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('next-photo')), findsOneWidget);
  });

  testWidgets('edge swipes show one centered notice without queuing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(
          CleanerState(FakeAppStore(database), FakeMediaRepository()),
          Scope.all,
          source: const [photo],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    for (var attempt = 0; attempt < 2; attempt++) {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('review-gesture'))),
      );
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      expect(
        tester
            .widget<Transform>(find.byKey(const Key('media-drag-translation')))
            .transform
            .storage[12],
        greaterThan(0),
      );
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump();
      expect(find.text('已经是第一张'), findsOneWidget);
    }

    final notice = find.byKey(const Key('edge-notice'));
    expect(notice, findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    final noticeDecoration =
        tester.widget<DecoratedBox>(notice).decoration as BoxDecoration;
    expect(noticeDecoration.color, const Color(0x70FFFFFF));
    expect(noticeDecoration.border, isNotNull);
    expect(
      tester.widget<Text>(find.text('已经是第一张')).style?.color,
      const Color(0xFF10131A),
    );
    expect(
      tester.widget<Text>(find.text('已经是第一张')).style?.decoration,
      TextDecoration.none,
    );
    expect(
      find.ancestor(of: notice, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );
    expect(
      tester.getCenter(notice).dy,
      closeTo(
        tester.view.physicalSize.height / tester.view.devicePixelRatio / 2,
        2,
      ),
    );

    final lastGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('review-gesture'))),
    );
    await lastGesture.moveBy(const Offset(-100, 0));
    await tester.pump();
    await lastGesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump();
    expect(find.byKey(const Key('edge-notice')), findsOneWidget);
    expect(find.text('已经是第一张'), findsNothing);
    expect(find.text('已经是最后一张'), findsOneWidget);
  });

  testWidgets('an upward swipe keeps the previous scale-only delete feedback', (
    tester,
  ) async {
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
    expect(find.byKey(const Key('delete-perspective')), findsNothing);
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

  testWidgets('an acted item leaves a source-backed review list', (
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
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('photo')), findsNothing);
    expect(find.byKey(const ValueKey('next-photo')), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
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
    expect(find.text('2 / 2'), findsOneWidget);
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

  testWidgets('settings no longer offers a downward skip action', (
    tester,
  ) async {
    final app = CleanerState(FakeAppStore(database), FakeMediaRepository());

    await tester.pumpWidget(MaterialApp(home: SettingsScreen(app)));

    final selector = tester.widget<SegmentedButton<DownSwipeAction>>(
      find.byType(SegmentedButton<DownSwipeAction>),
    );
    expect(selector.segments.map((segment) => segment.value), [
      DownSwipeAction.none,
      DownSwipeAction.pending,
      DownSwipeAction.returnToAlbum,
    ]);
    expect(find.text('跳过'), findsNothing);
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

  testWidgets('acting on the last item selects the previous remaining item', (
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

    expect(find.byKey(const ValueKey('next-photo')), findsNothing);
    expect(find.byKey(const ValueKey('photo')), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.text('本范围已整理完成'), findsNothing);
  });

  testWidgets('home categories include all media and albums use a grid', (
    tester,
  ) async {
    final app = CleanerState(
      ReviewedVideoScopeAppStore(database),
      AlbumsMediaRepository(),
    );

    await tester.pumpWidget(MaterialApp(home: HomeScreen(app)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-brand')), findsOneWidget);
    expect(find.byKey(const Key('home-brand-logo')), findsOneWidget);
    expect(find.text('相册删除'), findsOneWidget);
    expect(find.byKey(const ValueKey('category-all')), findsOneWidget);
    final allMediaSize = tester.getSize(
      find.byKey(const ValueKey('category-all')),
    );
    expect(
      allMediaSize.width / allMediaSize.height,
      moreOrLessEquals(4 / 3, epsilon: 0.01),
    );
    expect(
      tester.getSize(find.byKey(const Key('review-hero'))).height,
      lessThanOrEqualTo(100),
    );
    final allMediaGradient = tester.widget<DecoratedBox>(
      find.byKey(const Key('all-media-title-gradient')),
    );
    final gradient = (allMediaGradient.decoration as BoxDecoration).gradient!;
    expect((gradient as LinearGradient).colors.first.a, 0);
    expect(find.byKey(const ValueKey('all-media-cover-photo')), findsOneWidget);
    expect(find.byKey(const ValueKey('all-media-cover-video')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('all-media-cover-next-photo')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('all-media-cover-video-marker-video')),
      findsOneWidget,
    );
    final homeList = tester.widget<ListView>(find.byType(ListView));
    final homeChildren =
        (homeList.childrenDelegate as SliverChildListDelegate).children;
    expect(
      homeChildren.indexWhere(
        (child) => child.key == const Key('home-all-media-card'),
      ),
      lessThan(
        homeChildren.indexWhere(
          (child) => child.key == const ValueKey('section-分类整理'),
        ),
      ),
    );
    expect(find.text('全部照片与视频'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('category-grid')),
      300,
    );
    expect(find.byKey(const Key('category-grid')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('category-category:video')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('category-category:screenshot')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('category-category:selfie')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('category-category:live')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('category-similar')), findsOneWidget);

    await tester.tap(find.text('相册'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('system-album-grid')), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('QQ'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('photo grids adapt from three to eight columns', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Future<int> columnsAt(double logicalWidth) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(logicalWidth, 900);
      final app = CleanerState(ScopeAppStore(database), FakeMediaRepository());
      await tester.pumpWidget(MaterialApp(home: ScopeScreen(app, Scope.all)));
      await tester.pumpAndSettle();
      final grid = tester.widget<GridView>(
        find.byKey(const Key('scope-media-grid')),
      );
      return (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount;
    }

    expect(await columnsAt(320), 3);
    expect(await columnsAt(390), 4);
    expect(await columnsAt(600), 6);
    expect(await columnsAt(800), 8);
  });

  testWidgets('album grids keep two columns on phones and scale to four', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Future<int> columnsAt(double logicalWidth) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(logicalWidth, 900);
      final app = CleanerState(
        ScopeAppStore(database),
        AlbumsMediaRepository(),
      );
      await tester.pumpWidget(MaterialApp(home: HomeScreen(app)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('相册'));
      await tester.pumpAndSettle();
      final grid = tester.widget<GridView>(
        find.byKey(const Key('system-album-grid')),
      );
      return (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount;
    }

    expect(await columnsAt(390), 2);
    expect(await columnsAt(600), 3);
    expect(await columnsAt(840), 4);
  });

  testWidgets('similar photo groups open the existing review screen', (
    tester,
  ) async {
    final app = CleanerState(ScopeAppStore(database), SimilarMediaRepository());

    await tester.pumpWidget(MaterialApp(home: HomeScreen(app)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('category-similar')),
      300,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-similar')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('similar-groups')), findsOneWidget);
    expect(find.text('第 1 组 · 2 张'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('similar-photo')));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('photo')), findsOneWidget);
  });

  testWidgets(
    'media grids hide dates and all media only exposes pending when enabled',
    (tester) async {
      final store = ScopeAppStore(database);
      final app = CleanerState(store, FakeMediaRepository());

      await tester.pumpWidget(
        MaterialApp(home: ScopeScreen(app, Scope.month('2026-10'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('1970-01-01'), findsNothing);

      await tester.pumpWidget(MaterialApp(home: ScopeScreen(app, Scope.all)));
      await tester.pumpAndSettle();
      expect(find.text('1970-01-01'), findsNothing);
      expect(find.byKey(const Key('pending-filter-entry')), findsNothing);

      app.downAction = DownSwipeAction.pending;
      await tester.pumpWidget(MaterialApp(home: ScopeScreen(app, Scope.all)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pending-filter-entry')), findsOneWidget);

      await tester.tap(find.byKey(const Key('pending-filter-entry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('library-view-toggle')), findsNothing);
      expect(find.byKey(const Key('library-time-controls')), findsNothing);
    },
  );

  testWidgets('home navigation floats on glass and animates tab changes', (
    tester,
  ) async {
    final app = CleanerState(ScopeAppStore(database), AlbumsMediaRepository());

    await tester.pumpWidget(MaterialApp(home: HomeScreen(app)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-glass-nav')), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('更多'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('home-glass-nav')),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('相册'));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(FadeTransition), findsWidgets);
    await tester.pumpAndSettle();
  });

  testWidgets('library controls collapse on scroll and switch time ranges', (
    tester,
  ) async {
    final app = CleanerState(
      LongScopeAppStore(database, initialAnchor: 'photo-0'),
      AlbumsMediaRepository(),
    );
    app.months = [('2026-10', 3), ('2026-09', 2)];

    await tester.pumpWidget(MaterialApp(home: ScopeScreen(app, Scope.all)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-view-toggle')), findsOneWidget);
    expect(find.byKey(const Key('library-time-controls')), findsNothing);

    await tester.drag(
      find.byKey(const Key('scope-media-grid')),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-circle-button')), findsOneWidget);
    expect(find.byKey(const Key('library-time-controls')), findsOneWidget);
    final libraryGlass = tester
        .widgetList<DecoratedBox>(
          find.ancestor(
            of: find.byKey(const Key('library-circle-button')),
            matching: find.byType(DecoratedBox),
          ),
        )
        .first;
    expect(
      (libraryGlass.decoration as BoxDecoration).color,
      const Color(0x70FFFFFF),
    );
    final libraryIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('library-circle-button')),
        matching: find.byIcon(Icons.photo_library_outlined),
      ),
    );
    expect(libraryIcon.color, const Color(0xFF1557F8));
    final selectedMode = tester
        .widgetList<Material>(
          find.descendant(
            of: find.byKey(const ValueKey('library-mode-all')),
            matching: find.byType(Material),
          ),
        )
        .first;
    expect(selectedMode.color, const Color(0x8FE2E9FF));

    await tester.tap(find.byKey(const ValueKey('library-mode-month')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-month-grid')), findsOneWidget);
    expect(find.text('2026年10月'), findsOneWidget);
    expect(tester.getSize(find.text('2026年10月')).height, lessThan(28));

    await tester.tap(find.byKey(const Key('library-circle-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('相册'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-albums-view')), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
  });

  testWidgets('video thumbnails show duration at the bottom-right', (
    tester,
  ) async {
    final app = CleanerState(
      VideoScopeAppStore(database),
      FakeMediaRepository(),
    );

    await tester.pumpWidget(MaterialApp(home: ScopeScreen(app, Scope.videos)));
    await tester.pumpAndSettle();

    expect(find.text('0:08'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsNothing);
  });

  testWidgets('a reviewed video still opens the tapped video from all media', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScopeScreen(
          CleanerState(
            ReviewedVideoScopeAppStore(database),
            FakeMediaRepository(),
          ),
          Scope.all,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('0:08'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('video')), findsOneWidget);
  });

  testWidgets('pending review can restore and down only returns to its list', (
    tester,
  ) async {
    final store = UndoAppStore(database);
    final app = CleanerState(store, FakeMediaRepository())
      ..downAction = DownSwipeAction.pending;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            key: const Key('open-pending-review'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ReviewScreen(
                  app,
                  Scope.all,
                  pendingOnly: true,
                  source: const [photo, nextPhoto],
                ),
              ),
            ),
            child: const Text('打开待定'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-pending-review')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('pending-restore-control')),
        matching: find.byIcon(Icons.undo_rounded),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('pending-restore-control')));
    await tester.pumpAndSettle();
    expect(store.actions, [ReviewAction.restore]);
    expect(find.byKey(const ValueKey('next-photo')), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('next-photo'))),
    );
    await gesture.moveBy(const Offset(0, 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(ReviewScreen), findsNothing);
    expect(store.actions, [ReviewAction.restore]);
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

  testWidgets('the delete queue restores selections', (tester) async {
    final store = QueueAppStore(database, ['photo', 'next-photo']);

    await tester.pumpWidget(
      MaterialApp(
        home: QueueScreen(CleanerState(store, FakeMediaRepository())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.undo_rounded), findsNWidgets(3));
    expect(tester.widget<AppBar>(find.byType(AppBar)).primary, isTrue);
    expect(find.text('恢复 0 项'), findsOneWidget);
    expect(find.text('删除 0 项'), findsOneWidget);

    final firstItem = find.byKey(const ValueKey('queue-item-photo'));
    final firstSelector = find.byKey(const ValueKey('queue-select-photo'));
    final firstRestore = find.byKey(const ValueKey('queue-restore-photo'));
    expect(
      tester.getCenter(firstSelector).dx,
      greaterThan(tester.getCenter(firstItem).dx),
    );
    expect(
      tester.getCenter(firstSelector).dy,
      lessThan(tester.getCenter(firstItem).dy),
    );
    expect(
      tester.getCenter(firstRestore).dx,
      moreOrLessEquals(tester.getCenter(firstItem).dx, epsilon: 2),
    );
    expect(
      tester.getCenter(firstRestore).dy,
      greaterThan(tester.getCenter(firstItem).dy),
    );

    final restoreButton = find.byKey(const Key('queue-restore-selected'));
    final deleteButton = find.byKey(const Key('queue-delete-selected'));
    expect(
      tester.getSize(restoreButton).height,
      tester.getSize(deleteButton).height,
    );
    expect(
      tester.getSize(deleteButton).width / tester.getSize(restoreButton).width,
      moreOrLessEquals(1.5, epsilon: 0.03),
    );

    final gesture = await tester.startGesture(tester.getCenter(firstSelector));
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('queue-item-next-photo'))),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(find.text('恢复 2 项'), findsOneWidget);
    expect(find.text('删除 2 项'), findsOneWidget);

    await tester.tap(firstSelector);
    await tester.pump();
    expect(find.text('恢复 1 项'), findsOneWidget);

    await tester.tap(find.text('恢复 1 项'));
    await tester.pumpAndSettle();
    expect(store.ids, ['photo']);
    expect(find.byType(SnackBar), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('drag selection auto-scrolls while held at the queue edge', (
    tester,
  ) async {
    final store = QueueAppStore(
      database,
      List.generate(60, (index) => 'queued-$index'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: QueueScreen(CleanerState(store, FakeMediaRepository())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final gridFinder = find.byType(GridView);
    final grid = tester.widget<GridView>(gridFinder);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('queue-select-queued-0'))),
    );
    await gesture.moveTo(
      Offset(
        tester.getCenter(gridFinder).dx,
        tester.getBottomLeft(gridFinder).dy - 8,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(grid.controller!.offset, greaterThan(0));

    await gesture.up();
    await tester.pump();
  });

  testWidgets(
    'queue preview stays fitted and down swipe returns to the queue',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      QueuePreviewScreen(FakeMediaRepository(), photo),
                ),
              ),
              child: const Text('打开预览'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开预览'));
      await tester.pumpAndSettle();

      final viewer = tester.widget<InteractiveViewer>(
        find.byKey(const Key('queue-preview-zoom')),
      );
      expect(viewer.maxScale, 4);
      expect(viewer.panEnabled, isFalse);
      expect(viewer.boundaryMargin, EdgeInsets.zero);
      expect(find.byKey(const Key('queue-preview-back')), findsOneWidget);
      expect(find.text('下滑返回待删除列表'), findsOneWidget);

      await tester.drag(
        find.byKey(const Key('queue-preview-surface')),
        const Offset(0, 130),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QueuePreviewScreen), findsNothing);
    },
  );

  testWidgets('delete result reports cleaned items and estimated space', (
    tester,
  ) async {
    final store = QueueAppStore(database, ['photo']);
    await tester.pumpWidget(
      MaterialApp(
        home: QueueScreen(CleanerState(store, DeletingMediaRepository())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('删除 1 项'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续删除'));
    await tester.pumpAndSettle();

    expect(find.text('清理完成'), findsOneWidget);
    expect(find.text('本次清理 1 项'), findsOneWidget);
    expect(find.text('预计涉及空间 2.0 MB'), findsOneWidget);
  });
}
