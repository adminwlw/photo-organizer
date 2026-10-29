import 'package:album_cleaner/media_repository.dart';
import 'package:album_cleaner/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

void main() {
  test('Android 11 groups trash requests while Android 10 stays per item', () {
    expect(androidUsesSystemTrash(29), isFalse);
    expect(androidUsesSystemTrash(30), isTrue);
    expect(deleteRequestBatchSize(true, false), 1);
    expect(deleteRequestBatchSize(true, true), 2000);
    expect(deleteRequestBatchSize(false, true), 500);
  });

  test('photo hashes use Hamming distance and form representative groups', () {
    expect(photoHashDistance('0000000000000000', '0000000000000003'), 2);
    expect(
      groupSimilarPhotoHashes({
        'a': '0000000000000000',
        'b': '0000000000000001',
        'c': 'ffffffffffffffff',
        'd': 'fffffffffffffffe',
        'single': 'aaaaaaaaaaaaaaaa',
      }, maxDistance: 1),
      [
        ['a', 'b'],
        ['c', 'd'],
      ],
    );
  });

  test('similar hash groups are transitive and input-order independent', () {
    final forward = groupSimilarPhotoHashes({
      'a': '0000000000000000',
      'b': '0000000000000001',
      'c': '0000000000000003',
      'single': 'ffffffffffffffff',
    }, maxDistance: 1);
    final reversed = groupSimilarPhotoHashes({
      'single': 'ffffffffffffffff',
      'c': '0000000000000003',
      'b': '0000000000000001',
      'a': '0000000000000000',
    }, maxDistance: 1);

    expect(forward, [
      ['a', 'b', 'c'],
    ]);
    expect(reversed, forward);
  });

  test('similar photo keeper prefers resolution then recency', () {
    const olderLarge = MediaRecord(
      id: 'older-large',
      takenAt: 100,
      width: 3000,
      height: 2000,
      month: '2026-10',
      type: 1,
      duration: 0,
      screenshot: false,
      selfie: false,
      live: false,
    );
    const newerLarge = MediaRecord(
      id: 'newer-large',
      takenAt: 200,
      width: 3000,
      height: 2000,
      month: '2026-10',
      type: 1,
      duration: 0,
      screenshot: false,
      selfie: false,
      live: false,
    );
    const newestSmall = MediaRecord(
      id: 'newest-small',
      takenAt: 300,
      width: 1000,
      height: 1000,
      month: '2026-10',
      type: 1,
      duration: 0,
      screenshot: false,
      selfie: false,
      live: false,
    );

    expect(
      recommendedSimilarPhotoKeeper([newestSmall, olderLarge, newerLarge]).id,
      'newer-large',
    );
  });

  test('band index handles a large mostly-unique library', () {
    final hashes = <String, String>{};
    final mask = (BigInt.one << 64) - BigInt.one;
    var value = BigInt.one;
    for (var index = 0; index < 10000; index++) {
      value =
          (value * BigInt.parse('6364136223846793005') +
              BigInt.parse('1442695040888963407')) &
          mask;
      hashes['photo-$index'] = value.toRadixString(16).padLeft(16, '0');
    }

    expect(groupSimilarPhotoHashes(hashes), isEmpty);
  });

  test('iOS exposes every user-visible PhotoKit smart category', () {
    final expected = {
      PMDarwinAssetCollectionSubtype.smartAlbumPanoramas:
          SystemCategoryKind.panoramas,
      PMDarwinAssetCollectionSubtype.smartAlbumVideos:
          SystemCategoryKind.videos,
      PMDarwinAssetCollectionSubtype.smartAlbumFavorites:
          SystemCategoryKind.favorites,
      PMDarwinAssetCollectionSubtype.smartAlbumTimelapses:
          SystemCategoryKind.timelapses,
      PMDarwinAssetCollectionSubtype.smartAlbumRecentlyAdded:
          SystemCategoryKind.recentlyAdded,
      PMDarwinAssetCollectionSubtype.smartAlbumBursts:
          SystemCategoryKind.bursts,
      PMDarwinAssetCollectionSubtype.smartAlbumSlomoVideos:
          SystemCategoryKind.slowMotion,
      PMDarwinAssetCollectionSubtype.smartAlbumSelfPortraits:
          SystemCategoryKind.selfies,
      PMDarwinAssetCollectionSubtype.smartAlbumScreenshots:
          SystemCategoryKind.screenshots,
      PMDarwinAssetCollectionSubtype.smartAlbumDepthEffect:
          SystemCategoryKind.depthEffect,
      PMDarwinAssetCollectionSubtype.smartAlbumLivePhotos:
          SystemCategoryKind.live,
      PMDarwinAssetCollectionSubtype.smartAlbumAnimated:
          SystemCategoryKind.animated,
      PMDarwinAssetCollectionSubtype.smartAlbumLongExposures:
          SystemCategoryKind.longExposures,
      PMDarwinAssetCollectionSubtype.smartAlbumRAW: SystemCategoryKind.raw,
      PMDarwinAssetCollectionSubtype.smartAlbumCinematic:
          SystemCategoryKind.cinematic,
      PMDarwinAssetCollectionSubtype.smartAlbumSpatial:
          SystemCategoryKind.spatial,
      PMDarwinAssetCollectionSubtype.smartAlbumScreenRecordings:
          SystemCategoryKind.screenRecordings,
      PMDarwinAssetCollectionSubtype.smartAlbumReceipts:
          SystemCategoryKind.receipts,
      PMDarwinAssetCollectionSubtype.smartAlbumHandwriting:
          SystemCategoryKind.handwriting,
      PMDarwinAssetCollectionSubtype.smartAlbumIllustrations:
          SystemCategoryKind.illustrations,
      PMDarwinAssetCollectionSubtype.smartAlbumQRCodes:
          SystemCategoryKind.qrCodes,
    };

    for (final entry in expected.entries) {
      expect(iosSystemCategoryKind(entry.key), entry.value);
    }
    expect(
      iosSystemCategoryKind(PMDarwinAssetCollectionSubtype.smartAlbumAllHidden),
      isNull,
    );
    expect(
      iosSystemCategoryKind(PMDarwinAssetCollectionSubtype.smartAlbumProRes),
      isNull,
    );
    expect(
      iosSystemCategoryKind(
        PMDarwinAssetCollectionSubtype.smartAlbumUnableToUpload,
      ),
      isNull,
    );
    expect(
      iosSystemCategoryKind(
        PMDarwinAssetCollectionSubtype.smartAlbumUserLibrary,
      ),
      isNull,
    );
  });
}
