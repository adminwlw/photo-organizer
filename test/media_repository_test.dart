import 'package:album_cleaner/media_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

void main() {
  test('Android 10 deletes directly and Android 11 uses system trash', () {
    expect(androidUsesSystemTrash(29), isFalse);
    expect(androidUsesSystemTrash(30), isTrue);
    expect(deleteRequestBatchSize(true), 1);
    expect(deleteRequestBatchSize(false), 500);
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
          SystemCategoryKind.portraits,
      PMDarwinAssetCollectionSubtype.smartAlbumLivePhotos:
          SystemCategoryKind.live,
      PMDarwinAssetCollectionSubtype.smartAlbumAnimated:
          SystemCategoryKind.animated,
      PMDarwinAssetCollectionSubtype.smartAlbumLongExposures:
          SystemCategoryKind.longExposures,
      PMDarwinAssetCollectionSubtype.smartAlbumRAW: SystemCategoryKind.raw,
      PMDarwinAssetCollectionSubtype.smartAlbumCinematic:
          SystemCategoryKind.cinematic,
      PMDarwinAssetCollectionSubtype.smartAlbumProRes:
          SystemCategoryKind.proRes,
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
