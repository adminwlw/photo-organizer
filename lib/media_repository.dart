import 'dart:io';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import 'store.dart';

enum SystemAlbumGroup { album, people, smart }

bool androidUsesSystemTrash(int sdkInt) => sdkInt >= 30;

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
  videos,
  screenshots,
  live,
  selfies,
  portraits,
  spatialPhotos,
  spatialVideos,
}

class SystemCategorySummary {
  const SystemCategorySummary({
    required this.kind,
    required this.path,
    required this.count,
    required this.coverId,
    this.assetType,
  });

  final SystemCategoryKind kind;
  final AssetPathEntity path;
  final int count;
  final String? coverId;
  final AssetType? assetType;
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

class MediaRepository {
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
      final kind = switch (subtype) {
        PMDarwinAssetCollectionSubtype.smartAlbumVideos =>
          SystemCategoryKind.videos,
        PMDarwinAssetCollectionSubtype.smartAlbumScreenshots =>
          SystemCategoryKind.screenshots,
        PMDarwinAssetCollectionSubtype.smartAlbumLivePhotos =>
          SystemCategoryKind.live,
        PMDarwinAssetCollectionSubtype.smartAlbumSelfPortraits =>
          SystemCategoryKind.selfies,
        PMDarwinAssetCollectionSubtype.smartAlbumDepthEffect =>
          SystemCategoryKind.portraits,
        _ => null,
      };
      if (kind != null) {
        final count = await path.assetCountAsync;
        if (count == 0) continue;
        final cover = await path.getAssetListRange(start: 0, end: 1);
        result.add(
          SystemCategorySummary(
            kind: kind,
            path: path,
            count: count,
            coverId: cover.firstOrNull?.id,
          ),
        );
        continue;
      }
      if (subtype != PMDarwinAssetCollectionSubtype.smartAlbumSpatial) {
        continue;
      }
      final totals = <AssetType, int>{};
      final covers = <AssetType, String>{};
      for (var page = 0; ; page++) {
        final assets = await path.getAssetListPaged(page: page, size: 200);
        for (final asset in assets) {
          if (asset.type != AssetType.image && asset.type != AssetType.video) {
            continue;
          }
          totals[asset.type] = (totals[asset.type] ?? 0) + 1;
          covers.putIfAbsent(asset.type, () => asset.id);
        }
        if (assets.length < 200) break;
      }
      for (final type in [AssetType.image, AssetType.video]) {
        final count = totals[type] ?? 0;
        if (count == 0) continue;
        result.add(
          SystemCategorySummary(
            kind: type == AssetType.image
                ? SystemCategoryKind.spatialPhotos
                : SystemCategoryKind.spatialVideos,
            path: path,
            count: count,
            coverId: covers[type],
            assetType: type,
          ),
        );
      }
    }
    result.sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return result;
  }

  Future<List<MediaRecord>> recordsForAlbum(
    AssetPathEntity path,
    void Function(int, int) onProgress, {
    AssetType? assetType,
  }) async {
    final total = await path.assetCountAsync;
    final records = <MediaRecord>[];
    for (var page = 0; records.length < total; page++) {
      final assets = await path.getAssetListPaged(page: page, size: 200);
      if (assets.isEmpty) break;
      records.addAll(
        assets
            .where((asset) => assetType == null || asset.type == assetType)
            .map(_recordFromAsset),
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

  Future<File?> videoFile(String id) async {
    final asset = await get(id);
    if (asset?.type != AssetType.video) return null;
    return asset!.loadFile(isOrigin: false);
  }

  Future<bool> usesRecoverableTrash() async {
    if (!Platform.isAndroid) return true;
    return androidUsesSystemTrash(
      int.parse(await PhotoManager.systemVersion()),
    );
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
    for (var start = 0; start < assets.length; start += 500) {
      final batch = assets.skip(start).take(500).toList();
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
