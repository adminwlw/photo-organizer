import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:photo_manager/photo_manager.dart';

import 'store.dart';

enum SystemAlbumGroup { album, people, smart }

bool androidUsesSystemTrash(int sdkInt) => sdkInt >= 30;
int deleteRequestBatchSize(bool isAndroid, bool usesRecoverableTrash) =>
    isAndroid ? (usesRecoverableTrash ? 2000 : 1) : 500;

class SystemAlbumSummary {
  const SystemAlbumSummary({
    required this.path,
    required this.count,
    required this.coverId,
    required this.group,
  });

  final AssetPathEntity path;
  final int count;
  final String? coverId;
  final SystemAlbumGroup group;
}

enum SystemCategoryKind {
  generic,
  panoramas,
  videos,
  favorites,
  timelapses,
  recentlyAdded,
  bursts,
  slowMotion,
  screenshots,
  live,
  selfies,
  portraits,
  animated,
  longExposures,
  raw,
  cinematic,
  spatial,
  proRes,
  screenRecordings,
  receipts,
  handwriting,
  illustrations,
  qrCodes,
}

String systemCategoryLabel(
  SystemCategoryKind kind, {
  required String providerLabel,
  required String languageCode,
}) {
  if (languageCode.toLowerCase().startsWith('zh')) {
    return switch (kind) {
      SystemCategoryKind.generic => '系统分类',
      SystemCategoryKind.panoramas => '全景照片',
      SystemCategoryKind.videos => '视频',
      SystemCategoryKind.favorites => '个人收藏',
      SystemCategoryKind.timelapses => '延时摄影',
      SystemCategoryKind.recentlyAdded => '最近添加',
      SystemCategoryKind.bursts => '连拍快照',
      SystemCategoryKind.slowMotion => '慢动作',
      SystemCategoryKind.screenshots => '截屏',
      SystemCategoryKind.live => '实况照片',
      SystemCategoryKind.selfies => '自拍',
      SystemCategoryKind.portraits => '人像',
      SystemCategoryKind.animated => '动图',
      SystemCategoryKind.longExposures => '长曝光',
      SystemCategoryKind.raw => 'RAW',
      SystemCategoryKind.cinematic => '电影效果',
      SystemCategoryKind.spatial => '空间',
      SystemCategoryKind.proRes => 'ProRes',
      SystemCategoryKind.screenRecordings => '屏幕录制',
      SystemCategoryKind.receipts => '收据',
      SystemCategoryKind.handwriting => '手写内容',
      SystemCategoryKind.illustrations => '插图',
      SystemCategoryKind.qrCodes => '二维码',
    };
  }
  if (providerLabel.isNotEmpty) return providerLabel;
  return switch (kind) {
    SystemCategoryKind.generic => 'Smart Album',
    SystemCategoryKind.panoramas => 'Panoramas',
    SystemCategoryKind.videos => 'Videos',
    SystemCategoryKind.favorites => 'Favorites',
    SystemCategoryKind.timelapses => 'Time-lapse',
    SystemCategoryKind.recentlyAdded => 'Recently Added',
    SystemCategoryKind.bursts => 'Bursts',
    SystemCategoryKind.slowMotion => 'Slo-mo',
    SystemCategoryKind.screenshots => 'Screenshots',
    SystemCategoryKind.live => 'Live Photos',
    SystemCategoryKind.selfies => 'Selfies',
    SystemCategoryKind.portraits => 'Portrait',
    SystemCategoryKind.animated => 'Animated',
    SystemCategoryKind.longExposures => 'Long Exposure',
    SystemCategoryKind.raw => 'RAW',
    SystemCategoryKind.cinematic => 'Cinematic',
    SystemCategoryKind.spatial => 'Spatial',
    SystemCategoryKind.proRes => 'ProRes',
    SystemCategoryKind.screenRecordings => 'Screen Recordings',
    SystemCategoryKind.receipts => 'Receipts',
    SystemCategoryKind.handwriting => 'Handwriting',
    SystemCategoryKind.illustrations => 'Illustrations',
    SystemCategoryKind.qrCodes => 'QR Codes',
  };
}

SystemCategoryKind? iosSystemCategoryKind(
  PMDarwinAssetCollectionSubtype? subtype,
) => switch (subtype) {
  PMDarwinAssetCollectionSubtype.smartAlbumGeneric =>
    SystemCategoryKind.generic,
  PMDarwinAssetCollectionSubtype.smartAlbumPanoramas =>
    SystemCategoryKind.panoramas,
  PMDarwinAssetCollectionSubtype.smartAlbumVideos => SystemCategoryKind.videos,
  PMDarwinAssetCollectionSubtype.smartAlbumFavorites =>
    SystemCategoryKind.favorites,
  PMDarwinAssetCollectionSubtype.smartAlbumTimelapses =>
    SystemCategoryKind.timelapses,
  PMDarwinAssetCollectionSubtype.smartAlbumRecentlyAdded =>
    SystemCategoryKind.recentlyAdded,
  PMDarwinAssetCollectionSubtype.smartAlbumBursts => SystemCategoryKind.bursts,
  PMDarwinAssetCollectionSubtype.smartAlbumSlomoVideos =>
    SystemCategoryKind.slowMotion,
  PMDarwinAssetCollectionSubtype.smartAlbumSelfPortraits =>
    SystemCategoryKind.selfies,
  PMDarwinAssetCollectionSubtype.smartAlbumScreenshots =>
    SystemCategoryKind.screenshots,
  PMDarwinAssetCollectionSubtype.smartAlbumDepthEffect =>
    SystemCategoryKind.portraits,
  PMDarwinAssetCollectionSubtype.smartAlbumLivePhotos =>
    SystemCategoryKind.live,
  PMDarwinAssetCollectionSubtype.smartAlbumAnimated =>
    SystemCategoryKind.animated,
  PMDarwinAssetCollectionSubtype.smartAlbumLongExposures =>
    SystemCategoryKind.longExposures,
  PMDarwinAssetCollectionSubtype.smartAlbumRAW => SystemCategoryKind.raw,
  PMDarwinAssetCollectionSubtype.smartAlbumCinematic =>
    SystemCategoryKind.cinematic,
  PMDarwinAssetCollectionSubtype.smartAlbumSpatial =>
    SystemCategoryKind.spatial,
  PMDarwinAssetCollectionSubtype.smartAlbumProRes => SystemCategoryKind.proRes,
  PMDarwinAssetCollectionSubtype.smartAlbumScreenRecordings =>
    SystemCategoryKind.screenRecordings,
  PMDarwinAssetCollectionSubtype.smartAlbumReceipts =>
    SystemCategoryKind.receipts,
  PMDarwinAssetCollectionSubtype.smartAlbumHandwriting =>
    SystemCategoryKind.handwriting,
  PMDarwinAssetCollectionSubtype.smartAlbumIllustrations =>
    SystemCategoryKind.illustrations,
  PMDarwinAssetCollectionSubtype.smartAlbumQRCodes =>
    SystemCategoryKind.qrCodes,
  _ => null,
};

class SystemCategorySummary {
  const SystemCategorySummary({
    required this.kind,
    required this.label,
    required this.path,
    required this.count,
    required this.coverId,
  });

  final SystemCategoryKind kind;
  final String label;
  final AssetPathEntity path;
  final int count;
  final String? coverId;
}

class MediaStorageSummary {
  const MediaStorageSummary({
    required this.totalBytes,
    required this.photoBytes,
    required this.videoBytes,
    required this.screenshotBytes,
    required this.liveBytes,
    required this.unknownItems,
    required this.totalItems,
  });

  final int totalBytes;
  final int photoBytes;
  final int videoBytes;
  final int screenshotBytes;
  final int liveBytes;
  final int unknownItems;
  final int totalItems;
}

class SimilarPhotoGroup {
  const SimilarPhotoGroup(this.items);

  final List<MediaRecord> items;
}

int photoHashDistance(String left, String right) {
  var difference =
      BigInt.parse(left, radix: 16) ^ BigInt.parse(right, radix: 16);
  var distance = 0;
  while (difference != BigInt.zero) {
    difference &= difference - BigInt.one;
    distance++;
  }
  return distance;
}

List<List<String>> groupSimilarPhotoHashes(
  Map<String, String> hashes, {
  int maxDistance = 6,
}) {
  final groups = <List<String>>[];
  for (final entry in hashes.entries) {
    final group = groups.where(
      (candidate) =>
          photoHashDistance(entry.value, hashes[candidate.first]!) <=
          maxDistance,
    );
    if (group.isEmpty) {
      groups.add([entry.key]);
    } else {
      group.first.add(entry.key);
    }
  }
  return groups.where((group) => group.length > 1).toList();
}

class MediaRepository {
  bool get supportsLivePhotoPlayback => Platform.isIOS;

  Future<PermissionState> permission() => PhotoManager.getPermissionState(
    requestOption: const PermissionRequestOption(),
  );

  Future<PermissionState> requestPermission() =>
      PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(),
      );

  Future<void> managePermission(PermissionState state) async {
    if (state == PermissionState.limited) {
      await PhotoManager.presentLimited(type: RequestType.common);
    } else {
      await PhotoManager.openSetting();
    }
  }

  Future<void> scan(AppStore store, void Function(int) onProgress) async {
    final state = await permission();
    if (!state.hasAccess) return;
    final scanId = DateTime.now().microsecondsSinceEpoch;
    final selfieIds = <String>{};
    final screenshotIds = <String>{};
    if (Platform.isIOS) {
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: false,
      );
      for (final path in paths) {
        final target = switch (path.albumTypeEx?.darwin?.subtype) {
          PMDarwinAssetCollectionSubtype.smartAlbumSelfPortraits => selfieIds,
          PMDarwinAssetCollectionSubtype.smartAlbumScreenshots => screenshotIds,
          _ => null,
        };
        if (target == null) continue;
        for (var page = 0; ; page++) {
          final items = await path.getAssetListPaged(page: page, size: 200);
          target.addAll(items.map((item) => item.id));
          if (items.length < 200) break;
        }
      }
    }
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
    );
    if (paths.isEmpty) {
      await store.finishScan(scanId);
      return;
    }
    final all = paths.first;
    var indexed = 0;
    for (var page = 0; ; page++) {
      final assets = await all.getAssetListPaged(page: page, size: 200);
      if (assets.isEmpty) break;
      final records = <MediaRecord>[];
      for (final asset in assets) {
        if (asset.type != AssetType.image && asset.type != AssetType.video) {
          continue;
        }
        final path = asset.relativePath?.toLowerCase() ?? '';
        final title = asset.title?.toLowerCase() ?? '';
        records.add(
          _recordFromAsset(
            asset,
            screenshot:
                screenshotIds.contains(asset.id) ||
                (Platform.isAndroid &&
                    (path.contains('screenshot') ||
                        title.startsWith('screenshot'))),
            selfie: selfieIds.contains(asset.id),
          ),
        );
      }
      await store.upsertMediaPage(records, scanId);
      indexed += records.length;
      onProgress(indexed);
      if (assets.length < 200) break;
    }
    await store.finishScan(scanId);
  }

  MediaRecord _recordFromAsset(
    AssetEntity asset, {
    bool screenshot = false,
    bool selfie = false,
  }) {
    final seconds = asset.createDateSecond ?? asset.modifiedDateSecond ?? 0;
    final time = seconds > 0 ? seconds * 1000 : 0;
    final date = time == 0 ? null : DateTime.fromMillisecondsSinceEpoch(time);
    final month = date == null
        ? 'unknown'
        : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
    return MediaRecord(
      id: asset.id,
      takenAt: time,
      month: month,
      type: asset.type == AssetType.video ? 2 : 1,
      duration: asset.duration,
      screenshot: screenshot,
      selfie: selfie,
      live: asset.isLivePhoto,
    );
  }

  Future<List<SystemAlbumSummary>> systemAlbums() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      hasAll: false,
    );
    final result = <SystemAlbumSummary>[];
    for (final path in paths.where((path) => path.albumType == 1)) {
      final subtype = path.albumTypeEx?.darwin?.subtype;
      if (subtype == PMDarwinAssetCollectionSubtype.smartAlbumAllHidden ||
          subtype == PMDarwinAssetCollectionSubtype.smartAlbumUnableToUpload) {
        continue;
      }
      final count = await path.assetCountAsync;
      if (count == 0) continue;
      final cover = await path.getAssetListRange(start: 0, end: 1);
      final type = path.albumTypeEx?.darwin?.type;
      final group = subtype == PMDarwinAssetCollectionSubtype.albumSyncedFaces
          ? SystemAlbumGroup.people
          : type == PMDarwinAssetCollectionType.smartAlbum
          ? SystemAlbumGroup.smart
          : SystemAlbumGroup.album;
      result.add(
        SystemAlbumSummary(
          path: path,
          count: count,
          coverId: cover.firstOrNull?.id,
          group: group,
        ),
      );
    }
    result.sort((a, b) => b.count.compareTo(a.count));
    return result;
  }

  Future<List<SystemCategorySummary>> systemCategories() async {
    if (!Platform.isIOS) return const [];
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      hasAll: false,
    );
    final result = <SystemCategorySummary>[];
    for (final path in paths) {
      final subtype = path.albumTypeEx?.darwin?.subtype;
      final kind = iosSystemCategoryKind(subtype);
      if (kind != null) {
        final count = await path.assetCountAsync;
        if (count == 0) continue;
        final cover = await path.getAssetListRange(start: 0, end: 1);
        result.add(
          SystemCategorySummary(
            kind: kind,
            label: path.name.trim(),
            path: path,
            count: count,
            coverId: cover.firstOrNull?.id,
          ),
        );
        continue;
      }
    }
    return result;
  }

  Future<List<MediaRecord>> recordsForAlbum(
    AssetPathEntity path,
    void Function(int, int) onProgress,
  ) async {
    final total = await path.assetCountAsync;
    final records = <MediaRecord>[];
    for (var page = 0; records.length < total; page++) {
      final assets = await path.getAssetListPaged(page: page, size: 200);
      if (assets.isEmpty) break;
      records.addAll(assets.map(_recordFromAsset));
      onProgress(records.length, total);
      if (assets.length < 200) break;
    }
    return records;
  }

  Future<MediaStorageSummary> storageSummary(
    void Function(int, int) onProgress,
  ) async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
    );
    if (paths.isEmpty) {
      return const MediaStorageSummary(
        totalBytes: 0,
        photoBytes: 0,
        videoBytes: 0,
        screenshotBytes: 0,
        liveBytes: 0,
        unknownItems: 0,
        totalItems: 0,
      );
    }
    final screenshotIds = <String>{};
    if (Platform.isIOS) {
      final imagePaths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        hasAll: false,
      );
      for (final imagePath in imagePaths.where(
        (item) =>
            item.albumTypeEx?.darwin?.subtype ==
            PMDarwinAssetCollectionSubtype.smartAlbumScreenshots,
      )) {
        for (var page = 0; ; page++) {
          final items = await imagePath.getAssetListPaged(
            page: page,
            size: 200,
          );
          screenshotIds.addAll(items.map((item) => item.id));
          if (items.length < 200) break;
        }
      }
    }
    final path = paths.first;
    final total = await path.assetCountAsync;
    var processed = 0;
    var photoBytes = 0;
    var videoBytes = 0;
    var screenshotBytes = 0;
    var liveBytes = 0;
    var unknown = 0;
    for (var page = 0; processed < total; page++) {
      final assets = await path.getAssetListPaged(page: page, size: 120);
      if (assets.isEmpty) break;
      for (var start = 0; start < assets.length; start += 12) {
        final batch = assets.skip(start).take(12).toList();
        final sizes = await Future.wait(
          batch.map((asset) async {
            try {
              return await asset.fileSize;
            } catch (_) {
              return 0;
            }
          }),
        );
        for (var i = 0; i < batch.length; i++) {
          final bytes = sizes[i];
          if (bytes <= 0) {
            unknown++;
          } else if (batch[i].type == AssetType.video) {
            videoBytes += bytes;
          } else {
            final asset = batch[i];
            final relativePath = asset.relativePath?.toLowerCase() ?? '';
            final title = asset.title?.toLowerCase() ?? '';
            final isScreenshot =
                screenshotIds.contains(asset.id) ||
                (Platform.isAndroid &&
                    (relativePath.contains('screenshot') ||
                        title.startsWith('screenshot')));
            if (asset.isLivePhoto) {
              liveBytes += bytes;
            } else if (isScreenshot) {
              screenshotBytes += bytes;
            } else {
              photoBytes += bytes;
            }
          }
        }
        processed += batch.length;
        onProgress(processed, total);
      }
      if (assets.length < 120) break;
    }
    return MediaStorageSummary(
      totalBytes: photoBytes + videoBytes + screenshotBytes + liveBytes,
      photoBytes: photoBytes,
      videoBytes: videoBytes,
      screenshotBytes: screenshotBytes,
      liveBytes: liveBytes,
      unknownItems: unknown,
      totalItems: total,
    );
  }

  Future<AssetEntity?> get(String id) => AssetEntity.fromId(id);

  Future<Uint8List?> thumbnail(String id, int width, int height) async {
    final asset = await get(id);
    return asset?.thumbnailDataWithSize(
      ThumbnailSize(width, height),
      quality: 85,
    );
  }

  Future<String?> _similarityHash(String id) async {
    final bytes = await thumbnail(id, 96, 96);
    if (bytes == null) return null;
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 9,
      targetHeight: 8,
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final pixels = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (pixels == null || frame.image.width < 9 || frame.image.height < 8) {
          return null;
        }
        int brightness(int x, int y) {
          final offset = (y * frame.image.width + x) * 4;
          return pixels.getUint8(offset) * 299 +
              pixels.getUint8(offset + 1) * 587 +
              pixels.getUint8(offset + 2) * 114;
        }

        var hash = BigInt.zero;
        for (var y = 0; y < 8; y++) {
          for (var x = 0; x < 8; x++) {
            hash <<= 1;
            if (brightness(x, y) > brightness(x + 1, y)) {
              hash |= BigInt.one;
            }
          }
        }
        return hash.toRadixString(16).padLeft(16, '0');
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  Future<List<SimilarPhotoGroup>> findSimilarPhotos(
    AppStore store,
    void Function(int, int) onProgress,
  ) async {
    final photos = await store.photoRecords();
    final hashes = await store.similarityHashes();
    final missing = photos.where((photo) => !hashes.containsKey(photo.id));
    final missingPhotos = missing.toList();
    var processed = photos.length - missingPhotos.length;
    onProgress(processed, photos.length);
    for (var start = 0; start < missingPhotos.length; start += 8) {
      final batch = missingPhotos.skip(start).take(8).toList();
      final values = await Future.wait(
        batch.map((photo) async {
          try {
            return await _similarityHash(photo.id);
          } catch (_) {
            return null;
          }
        }),
      );
      for (var index = 0; index < batch.length; index++) {
        final hash = values[index];
        if (hash == null) continue;
        hashes[batch[index].id] = hash;
        await store.saveSimilarityHash(batch[index].id, hash);
      }
      processed += batch.length;
      onProgress(processed, photos.length);
    }
    final records = {for (final photo in photos) photo.id: photo};
    final orderedHashes = {
      for (final photo in photos) photo.id: ?hashes[photo.id],
    };
    return groupSimilarPhotoHashes(orderedHashes)
        .map((ids) => SimilarPhotoGroup([for (final id in ids) ?records[id]]))
        .toList();
  }

  Future<int> cachedSimilarPhotoCount(AppStore store) async {
    final photos = await store.photoRecords();
    final hashes = await store.similarityHashes();
    final cachedHashes = {
      for (final photo in photos) photo.id: ?hashes[photo.id],
    };
    return groupSimilarPhotoHashes(cachedHashes)
        .fold<int>(0, (total, group) => total + group.length);
  }

  Future<File?> videoFile(String id) async {
    final asset = await get(id);
    if (asset?.type != AssetType.video) return null;
    return asset!.loadFile(isOrigin: false);
  }

  Future<File?> livePhotoVideoFile(String id) async {
    if (!supportsLivePhotoPlayback) return null;
    final asset = await get(id);
    if (asset?.isLivePhoto != true) return null;
    return asset!.fileWithSubtype;
  }

  Future<bool> usesRecoverableTrash() async {
    if (!Platform.isAndroid) return true;
    return androidUsesSystemTrash(
      int.parse(await PhotoManager.systemVersion()),
    );
  }

  Future<Map<String, int>> mediaSizes(Iterable<String> ids) async {
    final result = <String, int>{};
    final list = ids.toList();
    for (var start = 0; start < list.length; start += 12) {
      final batch = list.skip(start).take(12).toList();
      final sizes = await Future.wait(
        batch.map((id) async {
          try {
            return await (await get(id))?.fileSize ?? 0;
          } catch (_) {
            return 0;
          }
        }),
      );
      for (var index = 0; index < batch.length; index++) {
        result[batch[index]] = sizes[index];
      }
    }
    return result;
  }

  Future<Map<String, String>> deleteReviewedMedia(
    AppStore store,
    List<String> ids,
  ) async {
    final result = <String, String>{};
    final usesTrash = await usesRecoverableTrash();
    final currentPermission = await permission();
    final assets = <AssetEntity>[];
    for (final id in ids) {
      final asset = await get(id);
      if (asset == null) {
        final status = currentPermission.isAuth ? 'missing' : 'unknown';
        result[id] = status;
        await store.setQueueStatus(id, status);
      } else {
        assets.add(asset);
      }
    }
    // Android 11+ supports one system trash request for up to 2000 items.
    // Android 10 only grants recoverable delete access one item at a time.
    final batchSize = deleteRequestBatchSize(Platform.isAndroid, usesTrash);
    for (var start = 0; start < assets.length; start += batchSize) {
      final batch = assets.skip(start).take(batchSize).toList();
      for (final asset in batch) {
        await store.setQueueStatus(asset.id, 'submitting');
      }
      List<String> returned;
      try {
        returned = Platform.isAndroid && usesTrash
            ? await PhotoManager.editor.android.moveToTrash(batch)
            : await PhotoManager.editor.deleteWithIds(
                batch.map((e) => e.id).toList(),
              );
      } catch (_) {
        for (final asset in batch) {
          result[asset.id] = 'unknown';
          await store.setQueueStatus(asset.id, 'unknown');
        }
        continue;
      }
      final afterPermission = await permission();
      for (final asset in batch) {
        final id = asset.id;
        if (!returned.contains(id)) {
          result[id] = 'cancelled';
          await store.setQueueStatus(id, 'queued');
          continue;
        }
        final now = await get(id);
        final confirmed =
            afterPermission == currentPermission &&
            (now == null || now.isTrashed);
        if (confirmed) {
          result[id] = 'confirmedRemoved';
          await store.removeFromQueue(id);
        } else {
          result[id] = 'unknown';
          await store.setQueueStatus(id, 'unknown');
        }
      }
    }
    return result;
  }
}
