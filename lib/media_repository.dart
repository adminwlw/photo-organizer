import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:photo_manager/photo_manager.dart';

import 'store.dart';

// Bump when fingerprint or grouping semantics change.
const similarityAlgorithmVersion = 2;
const similarityMaxDistance = 6;

class SimilarityScanCancelled implements Exception {}

MediaRecord recommendedSimilarPhotoKeeper(List<MediaRecord> items) =>
    items.reduce((best, item) {
      final bestPixels = best.width * best.height;
      final itemPixels = item.width * item.height;
      if (itemPixels != bestPixels) {
        return itemPixels > bestPixels ? item : best;
      }
      if (item.takenAt != best.takenAt) {
        return item.takenAt > best.takenAt ? item : best;
      }
      return item.id.compareTo(best.id) < 0 ? item : best;
    });

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
  depthEffect,
  animated,
  longExposures,
  raw,
  cinematic,
  spatial,
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
      SystemCategoryKind.depthEffect => '景深效果',
      SystemCategoryKind.animated => '动图',
      SystemCategoryKind.longExposures => '长曝光',
      SystemCategoryKind.raw => 'RAW',
      SystemCategoryKind.cinematic => '电影效果',
      SystemCategoryKind.spatial => '空间',
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
    SystemCategoryKind.depthEffect => 'Depth Effect',
    SystemCategoryKind.animated => 'Animated',
    SystemCategoryKind.longExposures => 'Long Exposure',
    SystemCategoryKind.raw => 'RAW',
    SystemCategoryKind.cinematic => 'Cinematic',
    SystemCategoryKind.spatial => 'Spatial',
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
    SystemCategoryKind.depthEffect,
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

class SimilarPhotoStatus {
  const SimilarPhotoStatus({
    required this.hasAnalysis,
    required this.groupCount,
    required this.photoCount,
    required this.needsUpdate,
    required this.generatedAt,
  });

  final bool hasAnalysis;
  final int groupCount;
  final int photoCount;
  final bool needsUpdate;
  final int? generatedAt;
}

int photoHashDistance(String left, String right) {
  return _photoHashBitDistance(
    BigInt.parse(left, radix: 16),
    BigInt.parse(right, radix: 16),
  );
}

int _photoHashBitDistance(BigInt left, BigInt right) {
  var difference = left ^ right;
  var distance = 0;
  while (difference != BigInt.zero) {
    difference &= difference - BigInt.one;
    distance++;
  }
  return distance;
}

List<List<String>> groupSimilarPhotoHashes(
  Map<String, String> hashes, {
  int maxDistance = similarityMaxDistance,
}) {
  if (maxDistance < 0 || maxDistance > 7) {
    throw ArgumentError.value(maxDistance, 'maxDistance', 'must be 0 to 7');
  }
  final entries =
      hashes.entries
          .where((entry) => entry.value.length == 16)
          .map((entry) => (entry.key, BigInt.tryParse(entry.value, radix: 16)))
          .where((entry) => entry.$2 != null)
          .map((entry) => (entry.$1, entry.$2!))
          .toList()
        ..sort((left, right) => left.$1.compareTo(right.$1));
  if (entries.length < 2) return const [];

  final parent = List<int>.generate(entries.length, (index) => index);
  final rank = List<int>.filled(entries.length, 0);
  int root(int index) {
    while (parent[index] != index) {
      parent[index] = parent[parent[index]];
      index = parent[index];
    }
    return index;
  }

  void union(int left, int right) {
    final leftRoot = root(left);
    final rightRoot = root(right);
    if (leftRoot == rightRoot) return;
    if (rank[leftRoot] < rank[rightRoot]) {
      parent[leftRoot] = rightRoot;
    } else if (rank[leftRoot] > rank[rightRoot]) {
      parent[rightRoot] = leftRoot;
    } else {
      parent[rightRoot] = leftRoot;
      rank[leftRoot]++;
    }
  }

  final exactRepresentatives = <BigInt, int>{};
  if (maxDistance == 0) {
    for (var index = 0; index < entries.length; index++) {
      final previous = exactRepresentatives[entries[index].$2];
      if (previous == null) {
        exactRepresentatives[entries[index].$2] = index;
      } else {
        union(index, previous);
      }
    }
  } else {
    final buckets = List.generate(8, (_) => <int, List<int>>{});
    for (var index = 0; index < entries.length; index++) {
      final hash = entries[index].$2;
      final exact = exactRepresentatives[hash];
      if (exact != null) {
        union(index, exact);
        continue;
      }
      exactRepresentatives[hash] = index;
      final candidates = <int>{};
      for (var band = 0; band < 8; band++) {
        final value = ((hash >> (band * 8)) & BigInt.from(0xff)).toInt();
        candidates.addAll(buckets[band][value] ?? const []);
      }
      for (final candidate in candidates) {
        if (_photoHashBitDistance(hash, entries[candidate].$2) <= maxDistance) {
          union(index, candidate);
        }
      }
      for (var band = 0; band < 8; band++) {
        final value = ((hash >> (band * 8)) & BigInt.from(0xff)).toInt();
        buckets[band].putIfAbsent(value, () => []).add(index);
      }
    }
  }

  final groups = <int, List<String>>{};
  for (var index = 0; index < entries.length; index++) {
    groups.putIfAbsent(root(index), () => []).add(entries[index].$1);
  }
  final result = groups.values.where((group) => group.length > 1).toList();
  result.sort((left, right) => left.first.compareTo(right.first));
  return result;
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
    final modifiedSeconds = asset.modifiedDateSecond ?? 0;
    final time = seconds > 0 ? seconds * 1000 : 0;
    final date = time == 0 ? null : DateTime.fromMillisecondsSinceEpoch(time);
    final month = date == null
        ? 'unknown'
        : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
    return MediaRecord(
      id: asset.id,
      takenAt: time,
      modifiedAt: modifiedSeconds > 0 ? modifiedSeconds * 1000 : 0,
      width: asset.width,
      height: asset.height,
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
          subtype == PMDarwinAssetCollectionSubtype.smartAlbumUnableToUpload ||
          subtype == PMDarwinAssetCollectionSubtype.smartAlbumProRes) {
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
    final seen = <String>{};
    for (var page = 0; records.length < total; page++) {
      final assets = await path.getAssetListPaged(page: page, size: 200);
      if (assets.isEmpty) break;
      records.addAll(
        assets.where((asset) => seen.add(asset.id)).map(_recordFromAsset),
      );
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

  Future<List<List<String>>> groupSimilarPhotoHashesInBackground(
    Map<String, String> hashes, {
    int maxDistance = similarityMaxDistance,
  }) => Isolate.run(
    () => groupSimilarPhotoHashes(hashes, maxDistance: maxDistance),
  );

  Future<List<List<String>>> _groupSimilarPhotoHashesReliably(
    Map<String, String> hashes,
  ) async {
    try {
      return await groupSimilarPhotoHashesInBackground(
        hashes,
        maxDistance: similarityMaxDistance,
      );
    } catch (_) {
      return groupSimilarPhotoHashes(
        hashes,
        maxDistance: similarityMaxDistance,
      );
    }
  }

  Future<List<SimilarPhotoGroup>> findSimilarPhotos(
    AppStore store,
    void Function(int, int) onProgress, {
    bool Function()? shouldCancel,
  }) async {
    void checkCancelled() {
      if (shouldCancel?.call() ?? false) {
        throw SimilarityScanCancelled();
      }
    }

    checkCancelled();
    final photos = await store.photoRecords();
    checkCancelled();
    final hashes = await store.similarityHashes(
      algorithmVersion: similarityAlgorithmVersion,
    );
    final cachedGroups = await store.similarityGroups(
      algorithmVersion: similarityAlgorithmVersion,
      maxDistance: similarityMaxDistance,
    );
    final missing = photos.where((photo) => !hashes.containsKey(photo.id));
    final missingPhotos = missing.toList();
    var processed = photos.length - missingPhotos.length;
    onProgress(processed, photos.length);
    checkCancelled();
    if (missingPhotos.isEmpty && cachedGroups != null) {
      return _similarPhotoGroups(photos, cachedGroups);
    }
    for (var start = 0; start < missingPhotos.length; start += 8) {
      checkCancelled();
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
      checkCancelled();
      for (var index = 0; index < batch.length; index++) {
        checkCancelled();
        final hash = values[index];
        if (hash == null) continue;
        hashes[batch[index].id] = hash;
        await store.saveSimilarityHash(
          batch[index],
          hash,
          algorithmVersion: similarityAlgorithmVersion,
        );
      }
      processed += batch.length;
      onProgress(processed, photos.length);
      checkCancelled();
    }
    final orderedHashes = {
      for (final photo in photos) photo.id: ?hashes[photo.id],
    };
    final groups = await _groupSimilarPhotoHashesReliably(orderedHashes);
    checkCancelled();
    await store.replaceSimilarityGroups(
      groups,
      algorithmVersion: similarityAlgorithmVersion,
      maxDistance: similarityMaxDistance,
    );
    return _similarPhotoGroups(photos, groups);
  }

  Future<int> cachedSimilarPhotoCount(AppStore store) async {
    final cachedGroups = await store.similarityGroups(
      algorithmVersion: similarityAlgorithmVersion,
      maxDistance: similarityMaxDistance,
    );
    if (cachedGroups != null) {
      return cachedGroups.fold<int>(0, (total, group) => total + group.length);
    }
    final photos = await store.photoRecords();
    final hashes = await store.similarityHashes(
      algorithmVersion: similarityAlgorithmVersion,
    );
    final cachedHashes = {
      for (final photo in photos) photo.id: ?hashes[photo.id],
    };
    return (await _groupSimilarPhotoHashesReliably(cachedHashes))
        .fold<int>(0, (total, group) => total + group.length);
  }

  Future<SimilarPhotoStatus> cachedSimilarPhotoStatus(AppStore store) async {
    final groups = await store.similarityGroups(
      algorithmVersion: similarityAlgorithmVersion,
      maxDistance: similarityMaxDistance,
    );
    if (groups == null) {
      return const SimilarPhotoStatus(
        hasAnalysis: false,
        groupCount: 0,
        photoCount: 0,
        needsUpdate: true,
        generatedAt: null,
      );
    }
    final photos = await store.photoRecords();
    final hashes = await store.similarityHashes(
      algorithmVersion: similarityAlgorithmVersion,
    );
    return SimilarPhotoStatus(
      hasAnalysis: true,
      groupCount: groups.length,
      photoCount: groups.fold<int>(0, (total, group) => total + group.length),
      needsUpdate: hashes.length < photos.length,
      generatedAt: await cachedSimilarityGeneratedAt(store),
    );
  }

  Future<List<SimilarPhotoGroup>?> cachedSimilarPhotos(AppStore store) async {
    final groups = await store.similarityGroups(
      algorithmVersion: similarityAlgorithmVersion,
      maxDistance: similarityMaxDistance,
    );
    if (groups == null) return null;
    return _similarPhotoGroups(await store.photoRecords(), groups);
  }

  Future<int?> cachedSimilarityGeneratedAt(AppStore store) =>
      store.similarityGeneratedAt(
        algorithmVersion: similarityAlgorithmVersion,
        maxDistance: similarityMaxDistance,
      );

  List<SimilarPhotoGroup> _similarPhotoGroups(
    List<MediaRecord> photos,
    List<List<String>> groups,
  ) {
    final records = {for (final photo in photos) photo.id: photo};
    final order = {
      for (var index = 0; index < photos.length; index++)
        photos[index].id: index,
    };
    final result = groups
        .map(
          (ids) => [
            for (final id in ids) ?records[id],
          ]..sort((left, right) => order[left.id]!.compareTo(order[right.id]!)),
        )
        .where((items) => items.length > 1)
        .map(SimilarPhotoGroup.new)
        .toList();
    result.sort(
      (left, right) =>
          order[left.items.first.id]!.compareTo(order[right.items.first.id]!),
    );
    return result;
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
