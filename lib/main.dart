import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import 'media_repository.dart';
import 'store.dart';

const _systemBlue = Color(0xFF007AFF);
const _systemRed = Color(0xFFFF3B30);
const _systemBackground = Color(0xFFF2F2F7);
const _secondarySystemBackground = Color(0xFFFFFFFF);
const _primaryLabel = Color(0xFF000000);
const _secondaryLabel = Color(0x993C3C43);
const _tertiaryLabel = Color(0x4D3C3C43);
const _separator = Color(0x1F3C3C43);
const _appleGlass = Color(0x4DFFFFFF);
const _appleGlassBorder = Color(0x99FFFFFF);
const _appleGlassForeground = Color(0xE61C1C1E);
const _hardwareVolumeChannel = EventChannel(
  'com.sim360.albumcleaner/hardware_volume',
);
final Stream<void> _hardwareVolumeButtonEvents = _hardwareVolumeChannel
    .receiveBroadcastStream()
    .map((_) {});

enum DownSwipeAction { none, pending, returnToAlbum }

extension on DownSwipeAction {
  ReviewAction? get reviewAction => switch (this) {
    DownSwipeAction.none => null,
    DownSwipeAction.pending => ReviewAction.pending,
    DownSwipeAction.returnToAlbum => null,
  };

  String get label => switch (this) {
    DownSwipeAction.none => '无',
    DownSwipeAction.pending => '待定',
    DownSwipeAction.returnToAlbum => '返回相册',
  };
}

String _formatResultBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  final gb = bytes / (1024 * 1024 * 1024);
  if (gb >= 1) return '${gb.toStringAsFixed(gb >= 10 ? 1 : 2)} GB';
  final mb = bytes / (1024 * 1024);
  if (mb >= 1) return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  final kb = bytes / 1024;
  return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
}

String _formatMediaDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remaining = seconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${remaining.toString().padLeft(2, '0')}';
  }
  return '$minutes:${remaining.toString().padLeft(2, '0')}';
}

String _formatMediaDate(int milliseconds) {
  if (milliseconds <= 0) return '日期未知';
  final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  return '${date.year}年${date.month}月${date.day}日';
}

String _formatSimilarityGeneratedAt(int milliseconds) {
  final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${date.year}/${twoDigits(date.month)}/${twoDigits(date.day)} '
      '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
}

MediaRecord _mediaRecordFromAsset(String id, AssetEntity asset) => MediaRecord(
  id: id,
  takenAt: asset.createDateSecond == null ? 0 : asset.createDateSecond! * 1000,
  month: 'unknown',
  type: asset.type == AssetType.video ? 2 : 1,
  duration: asset.duration,
  screenshot: false,
  selfie: false,
  live: asset.isLivePhoto,
);

int _photoGridColumnCount(double logicalWidth) {
  const horizontalPadding = 40.0;
  const spacing = 6.0;
  const maxTileWidth = 100.0;
  final contentWidth = logicalWidth - horizontalPadding;
  return ((contentWidth + spacing) / (maxTileWidth + spacing)).ceil().clamp(
    3,
    8,
  );
}

int _albumGridColumnCount(double logicalWidth) {
  const horizontalPadding = 40.0;
  const spacing = 12.0;
  const maxTileWidth = 220.0;
  final contentWidth = logicalWidth - horizontalPadding;
  return ((contentWidth + spacing) / (maxTileWidth + spacing)).ceil().clamp(
    2,
    4,
  );
}

Future<Set<String>> _queuedMediaIds(AppStore store) async =>
    (await store.queue()).map((row) => row['media_id'] as String).toSet();

Future<List<MediaRecord>> _visibleAlbumRecords(
  MediaRepository media,
  AssetPathEntity path,
  Set<String> excludedIds,
) async {
  final records = await media.recordsForAlbum(path, (_, _) {});
  final visible = <String, MediaRecord>{};
  for (final record in records) {
    if (!excludedIds.contains(record.id)) {
      visible.putIfAbsent(record.id, () => record);
    }
  }
  return visible.values.toList();
}

Future<List<SystemAlbumSummary>> _loadVisibleSystemAlbums(
  CleanerState app,
) async {
  final summaries = await app.media.systemAlbums();
  final excludedIds = await _queuedMediaIds(app.store);
  if (excludedIds.isEmpty) return summaries;
  final result = <SystemAlbumSummary>[];
  for (final summary in summaries) {
    final visible = await _visibleAlbumRecords(
      app.media,
      summary.path,
      excludedIds,
    );
    if (visible.isEmpty) continue;
    result.add(
      SystemAlbumSummary(
        path: summary.path,
        count: visible.length,
        coverId: visible.first.id,
        group: summary.group,
      ),
    );
  }
  return result;
}

Future<List<SystemCategorySummary>> _loadVisibleSystemCategories(
  CleanerState app,
) async {
  final summaries = await app.media.systemCategories();
  final excludedIds = await _queuedMediaIds(app.store);
  if (excludedIds.isEmpty) return summaries;
  final result = <SystemCategorySummary>[];
  for (final summary in summaries) {
    final visible = await _visibleAlbumRecords(
      app.media,
      summary.path,
      excludedIds,
    );
    if (visible.isEmpty) continue;
    result.add(
      SystemCategorySummary(
        kind: summary.kind,
        label: summary.label,
        path: summary.path,
        count: visible.length,
        coverId: visible.first.id,
      ),
    );
  }
  return result;
}

double _appHeaderInset(BuildContext context) =>
    MediaQuery.paddingOf(context).top + 60;

const _immersiveHeaderHeight = 88.0;
const _immersiveHeaderPadding = EdgeInsets.fromLTRB(14, 8, 14, 14);

class _SystemTopGradient extends StatelessWidget {
  const _SystemTopGradient({super.key});

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
    ),
    child: IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(
          widthFactor: 1,
          heightFactor: 0.76,
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x2EFFFFFF),
                      Color(0x12FFFFFF),
                      Color(0x00FFFFFF),
                    ],
                    stops: [0, 0.62, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _GlassSurface extends StatelessWidget {
  const _GlassSurface({
    super.key,
    required this.child,
    this.color = _appleGlass,
    this.radius = 20,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final Color color;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x18000000),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: _appleGlassBorder, width: 0.8),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    ),
  );
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    super.key,
    this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.diameter = 42,
    this.iconSize = 20,
    this.color = _appleGlass,
    this.foregroundColor = _appleGlassForeground,
  });

  final Key? buttonKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double diameter;
  final double iconSize;
  final Color color;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) => _GlassSurface(
    color: color,
    radius: diameter / 2,
    child: IconButton(
      key: buttonKey,
      tooltip: tooltip,
      onPressed: onPressed,
      color: foregroundColor,
      disabledColor: const Color(0x663C3C43),
      constraints: BoxConstraints.tightFor(width: diameter, height: diameter),
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: iconSize),
    ),
  );
}

class _GlassActionButton extends StatelessWidget {
  const _GlassActionButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.foregroundColor = _appleGlassForeground,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) => _GlassSurface(
    radius: 18,
    child: TextButton.icon(
      key: buttonKey,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: foregroundColor,
        disabledForegroundColor: const Color(0x663C3C43),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      icon: Icon(icon),
      label: Text(label),
    ),
  );
}

class _AppleZoomableMedia extends StatefulWidget {
  const _AppleZoomableMedia({
    super.key,
    required this.child,
    this.surfaceKey,
    this.viewerKey,
    this.onSwipeUpdate,
    this.onSwipeEnd,
    this.onSwipeCancel,
    this.onZoomChanged,
  });

  final Widget child;
  final Key? surfaceKey;
  final Key? viewerKey;
  final ValueChanged<Offset>? onSwipeUpdate;
  final Future<void> Function(Velocity velocity)? onSwipeEnd;
  final VoidCallback? onSwipeCancel;
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<_AppleZoomableMedia> createState() => _AppleZoomableMediaState();
}

class _AppleZoomableMediaState extends State<_AppleZoomableMedia>
    with SingleTickerProviderStateMixin {
  static const _doubleTapScale = 2.5;
  static const _maxScale = 5.0;

  final transformation = TransformationController();
  final pointers = <int>{};
  late final AnimationController animation;
  Animation<Matrix4>? matrixAnimation;
  VelocityTracker? velocityTracker;
  int? swipePointer;
  Offset? doubleTapPosition;
  double swipeDistance = 0;
  bool zoomed = false;

  @override
  void initState() {
    super.initState();
    animation =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 240),
        )..addListener(() {
          final current = matrixAnimation;
          if (current == null) return;
          transformation.value = current.value;
          _syncZoom();
        });
  }

  @override
  void dispose() {
    animation.dispose();
    transformation.dispose();
    super.dispose();
  }

  void _syncZoom() {
    final next = transformation.value.getMaxScaleOnAxis() > 1.01;
    if (next == zoomed) return;
    zoomed = next;
    widget.onZoomChanged?.call(next);
    if (mounted) setState(() {});
  }

  void _animateTo(Matrix4 target) {
    animation.stop();
    matrixAnimation = Matrix4Tween(
      begin: transformation.value.clone(),
      end: target,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    animation.forward(from: 0);
  }

  void _onDoubleTap() {
    if (zoomed) {
      _animateTo(Matrix4.identity());
      return;
    }
    final point = doubleTapPosition ?? Offset.zero;
    final target = Matrix4.diagonal3Values(_doubleTapScale, _doubleTapScale, 1)
      ..setTranslationRaw(
        -point.dx * (_doubleTapScale - 1),
        -point.dy * (_doubleTapScale - 1),
        0,
      );
    _animateTo(target);
  }

  void _pointerDown(PointerDownEvent event) {
    pointers.add(event.pointer);
    if (pointers.length == 1 && !zoomed) {
      swipePointer = event.pointer;
      swipeDistance = 0;
      velocityTracker = VelocityTracker.withKind(event.kind)
        ..addPosition(event.timeStamp, event.position);
      return;
    }
    if (pointers.length == 2 && swipePointer != null) {
      swipePointer = null;
      velocityTracker = null;
      swipeDistance = 0;
      widget.onSwipeCancel?.call();
    }
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != swipePointer || pointers.length != 1 || zoomed) return;
    velocityTracker?.addPosition(event.timeStamp, event.position);
    swipeDistance += event.delta.distance;
    widget.onSwipeUpdate?.call(event.delta);
  }

  void _pointerUp(PointerUpEvent event) {
    final active = event.pointer == swipePointer && !zoomed;
    velocityTracker?.addPosition(event.timeStamp, event.position);
    final velocity = velocityTracker?.getVelocity() ?? Velocity.zero;
    pointers.remove(event.pointer);
    swipePointer = null;
    velocityTracker = null;
    if (active && swipeDistance >= 2) {
      final callback = widget.onSwipeEnd;
      if (callback != null) unawaited(callback(velocity));
    }
    swipeDistance = 0;
  }

  void _pointerCancel(PointerCancelEvent event) {
    pointers.remove(event.pointer);
    if (event.pointer != swipePointer) return;
    swipePointer = null;
    velocityTracker = null;
    swipeDistance = 0;
    widget.onSwipeCancel?.call();
  }

  @override
  Widget build(BuildContext context) => Listener(
    key: widget.surfaceKey,
    behavior: HitTestBehavior.opaque,
    onPointerDown: _pointerDown,
    onPointerMove: _pointerMove,
    onPointerUp: _pointerUp,
    onPointerCancel: _pointerCancel,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTapDown: (details) => doubleTapPosition = details.localPosition,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        key: widget.viewerKey,
        transformationController: transformation,
        minScale: 1,
        maxScale: _maxScale,
        panEnabled: zoomed,
        boundaryMargin: EdgeInsets.zero,
        onInteractionStart: (_) => animation.stop(),
        onInteractionUpdate: (_) => _syncZoom(),
        onInteractionEnd: (_) {
          if (transformation.value.getMaxScaleOnAxis() <= 1.01) {
            _animateTo(Matrix4.identity());
          } else {
            _syncZoom();
          }
        },
        child: SizedBox.expand(child: widget.child),
      ),
    ),
  );
}

class _SelectedNavIcon extends StatelessWidget {
  const _SelectedNavIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('home-selected-tab-circle'),
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: const Color(0xD9FFFFFF),
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xF2FFFFFF), width: 0.8),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1F1557F8),
          blurRadius: 10,
          offset: Offset(0, 3),
        ),
      ],
    ),
    alignment: Alignment.center,
    child: Icon(icon, color: _systemBlue, size: 23),
  );
}

class _UnifiedAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _UnifiedAppBar({required this.title, this.subtitle, this.actions});

  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) => AppBar(
    key: const Key('media-gradient-app-bar'),
    primary: true,
    toolbarHeight: 60,
    automaticallyImplyLeading: false,
    forceMaterialTransparency: true,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
    ),
    titleTextStyle: const TextStyle(
      color: _appleGlassForeground,
      fontSize: 17,
      fontWeight: FontWeight.w600,
    ),
    flexibleSpace: const _SystemTopGradient(key: Key('media-header-gradient')),
    leadingWidth: 58,
    leading: Navigator.canPop(context)
        ? Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Center(
              child: _GlassIconButton(
                key: const Key('media-header-back'),
                tooltip: '返回',
                icon: Icons.arrow_back_ios_new_rounded,
                onPressed: () => Navigator.maybePop(context),
                diameter: 44,
                iconSize: 19,
              ),
            ),
          )
        : null,
    titleSpacing: Navigator.canPop(context) ? 0 : 16,
    title: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _appleGlassForeground,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.12,
          ),
        ),
        if (subtitle case final subtitle?) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _secondaryLabel,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    ),
    actions: actions,
  );
}

class _HeaderSelectButton extends StatelessWidget {
  const _HeaderSelectButton({required this.selecting, required this.onPressed});

  final bool selecting;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: Center(
      child: _GlassSurface(
        radius: 18,
        child: TextButton(
          key: const Key('media-select-button'),
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: _appleGlassForeground,
            disabledForegroundColor: const Color(0x663C3C43),
            backgroundColor: Colors.transparent,
            minimumSize: const Size(62, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          child: Text(selecting ? '取消' : '选择'),
        ),
      ),
    ),
  );
}

class _HeaderBrowseButton extends StatelessWidget {
  const _HeaderBrowseButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Center(
      child: _GlassIconButton(
        tooltip: '左右滑动浏览',
        icon: Icons.swipe_rounded,
        onPressed: onPressed,
        diameter: 44,
        iconSize: 20,
      ),
    ),
  );
}

class _LivePhotoBadge extends StatelessWidget {
  const _LivePhotoBadge({this.showLabel = false});

  final bool showLabel;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: showLabel ? 8 : 5, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xB3000000),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0x66FFFFFF)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.motion_photos_on_rounded,
          color: Colors.white,
          size: 15,
        ),
        if (showLabel) ...[
          const SizedBox(width: 4),
          const Text(
            '实况',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
      ],
    ),
  );
}

class _SelectionMarker extends StatelessWidget {
  const _SelectionMarker({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(
      color: selected ? _systemBlue : const Color(0x66000000),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
    ),
    child: selected
        ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
        : null,
  );
}

class _BatchQueueBar extends StatelessWidget {
  const _BatchQueueBar({
    required this.selectedCount,
    required this.busy,
    required this.onQueue,
  });

  final int selectedCount;
  final bool busy;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) => SafeArea(
    minimum: EdgeInsets.zero,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: ClipRect(
        key: const Key('batch-queue-bar'),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: 66,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: const BoxDecoration(
              color: Color(0xE6F9F9F9),
              border: Border(top: BorderSide(color: _separator, width: 0.5)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('batch-queue-button'),
                onPressed: busy || selectedCount == 0 ? null : onQueue,
                style: FilledButton.styleFrom(
                  backgroundColor: _systemBlue,
                  disabledBackgroundColor: const Color(0x33787880),
                ),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text(busy ? '正在加入…' : '加入待删除 $selectedCount 项'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BootstrapApp());
}

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key, this.openStore, this.createMedia});

  final Future<AppStore> Function()? openStore;
  final MediaRepository Function()? createMedia;

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  CleanerState? app;
  Object? error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() => error = null);
    try {
      final store = await (widget.openStore ?? AppStore.open)();
      if (!mounted) {
        await store.close();
        return;
      }
      setState(() {
        app = CleanerState(
          store,
          (widget.createMedia ?? MediaRepository.new)(),
        );
      });
    } catch (caught) {
      if (mounted) setState(() => error = caught);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = app;
    if (current != null) return CleanerApp(current);
    return _StartupScreen(error: error, onRetry: _open);
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen({this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '相册删除',
    debugShowCheckedModeBanner: false,
    home: _StartupBrand(error: error, onRetry: onRetry),
  );
}

class _StartupBrand extends StatelessWidget {
  const _StartupBrand({this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _systemBackground,
    body: Stack(
      fit: StackFit.expand,
      children: [
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 84,
          child: _SystemTopGradient(key: Key('page-top-gradient')),
        ),
        SafeArea(
          child: Center(
            child: Column(
              key: const Key('startup-brand'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF35C9F2), Color(0xFF246BEB)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.photo_library_rounded,
                    color: Colors.white,
                    size: 46,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '相册删除',
                  style: TextStyle(
                    color: _primaryLabel,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                if (error == null)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else ...[
                  const Text(
                    '启动失败，请重试',
                    style: TextStyle(color: _secondaryLabel),
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: onRetry, child: const Text('重试')),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class CleanerState extends ChangeNotifier {
  CleanerState(this.store, this.media);
  final AppStore store;
  final MediaRepository media;
  bool ready = false;
  bool onboarded = false;
  bool scanning = false;
  bool scanFailed = false;
  int scanRevision = 0;
  PermissionState? permissionState;
  DownSwipeAction downAction = DownSwipeAction.returnToAlbum;
  List<(String, int)> months = [];
  MediaStorageSummary? storageSummary;
  Future<MediaStorageSummary>? _storageSummaryFuture;

  Future<MediaStorageSummary> loadStorageSummary(
    void Function(int, int) onProgress,
  ) async {
    final cached = storageSummary;
    if (cached != null) return cached;
    final pending = _storageSummaryFuture;
    if (pending != null) return pending;
    final request = media.storageSummary(onProgress);
    _storageSummaryFuture = request;
    try {
      final result = await request;
      storageSummary = result;
      return result;
    } finally {
      _storageSummaryFuture = null;
    }
  }

  void invalidateStorageSummary() {
    storageSummary = null;
    _storageSummaryFuture = null;
  }

  Future<void> initialize() async {
    final onboardedRequest = store.setting('onboarded');
    final downActionRequest = store.setting('down_swipe_action');
    final monthsRequest = store.months();
    final permissionRequest = media.permission();
    onboarded = await onboardedRequest == '1';
    downAction = switch (await downActionRequest) {
      'pending' || 'undecided' => DownSwipeAction.pending,
      'keep' || 'returnToAlbum' || 'skip' => DownSwipeAction.returnToAlbum,
      'none' => DownSwipeAction.none,
      _ => DownSwipeAction.returnToAlbum,
    };
    months = await monthsRequest;
    permissionState = await permissionRequest;
    ready = true;
    notifyListeners();
  }

  Future<void> finishOnboarding() async {
    await store.setSetting('onboarded', '1');
    onboarded = true;
    permissionState = await media.requestPermission();
    notifyListeners();
    if (permissionState!.hasAccess) await refresh();
  }

  Future<void> requestPermission() async {
    permissionState = await media.requestPermission();
    notifyListeners();
    if (permissionState!.hasAccess) await refresh();
  }

  Future<void> managePermission() async {
    await media.managePermission(permissionState!);
    await refresh();
  }

  Future<void> setDownAction(DownSwipeAction action) async {
    await store.setSetting('down_swipe_action', action.name);
    downAction = action;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (scanning) return;
    permissionState = await media.permission();
    if (!permissionState!.hasAccess) {
      notifyListeners();
      return;
    }
    scanning = true;
    scanFailed = false;
    try {
      await media.scan(store, (_) {});
      months = await store.months();
      scanRevision++;
    } catch (_) {
      scanFailed = true;
    } finally {
      scanning = false;
      notifyListeners();
    }
  }
}

class CleanerApp extends StatefulWidget {
  const CleanerApp(this.state, {super.key});
  final CleanerState state;

  @override
  State<CleanerApp> createState() => _CleanerAppState();
}

class _CleanerAppState extends State<CleanerApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    await widget.state.initialize();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.state.onboarded &&
          widget.state.permissionState?.hasAccess == true) {
        unawaited(widget.state.refresh());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.store.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.state.onboarded) {
      widget.state.refresh();
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '相册删除',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: const ColorScheme.light(
        primary: _systemBlue,
        onPrimary: Colors.white,
        secondary: _systemBlue,
        onSecondary: Colors.white,
        surface: _secondarySystemBackground,
        onSurface: _primaryLabel,
        error: _systemRed,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: _systemBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 52,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: _secondarySystemBackground,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _systemBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(44, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _systemBlue,
          backgroundColor: Colors.transparent,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w400),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _systemBlue,
          backgroundColor: _secondarySystemBackground,
          minimumSize: const Size(44, 50),
          side: const BorderSide(color: _separator),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: _systemBlue,
          backgroundColor: _secondarySystemBackground,
          elevation: 0,
          minimumSize: const Size(44, 50),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: _systemBlue,
          minimumSize: const Size(44, 44),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: _separator,
        thickness: 0.5,
        space: 0.5,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: _systemBlue,
        textColor: _primaryLabel,
        minTileHeight: 56,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xF2FFFFFF),
        surfaceTintColor: Colors.transparent,
        elevation: 18,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _secondarySystemBackground,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xE61C1C1E),
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const CircleBorder(),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? _systemBlue
              : Colors.transparent,
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 52,
        backgroundColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.fromMap({
          WidgetState.selected: IconThemeData(color: _systemBlue, size: 25),
          WidgetState.any: IconThemeData(color: _secondaryLabel, size: 24),
        }),
        labelTextStyle: WidgetStateProperty.fromMap({
          WidgetState.selected: TextStyle(
            color: _systemBlue,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
          WidgetState.any: TextStyle(
            color: _secondaryLabel,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        }),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      useMaterial3: true,
    ),
    home: AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final app = widget.state;
        if (!app.ready) {
          return const _StartupBrand();
        }
        if (!app.onboarded) {
          return OnboardingScreen(
            downAction: app.downAction,
            onDone: app.finishOnboarding,
          );
        }
        if (!app.permissionState!.hasAccess) return PermissionScreen(app);
        return HomeScreen(app);
      },
    ),
  );
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.downAction,
    required this.onDone,
    super.key,
  });
  final DownSwipeAction downAction;
  final Future<void> Function() onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  static const pageTitles = ['浏览照片', '加入待删除', '返回相册', '批量删除', '授权开始使用'];
  static const pageDescriptions = [
    '左右轻扫查看上一张或下一张，双击或双指可放大细节。',
    '上滑只会加入待删除队列，不会立即删除；仍可在队列中改为保留。',
    '下滑默认退出当前照片，返回正在整理的相册列表。',
    '进入待删除队列，勾选照片后批量删除；未选中的照片继续保留。',
    '首次使用请选择最上方的完整访问选项，才能整理整个图库。照片只在本机处理。',
  ];
  final PageController pager = PageController();
  late final AnimationController motionController;
  Timer? playbackTimer;
  int page = 0;
  bool busy = false;
  bool reduceMotion = false;

  @override
  void initState() {
    super.initState();
    motionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _schedulePlayback();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduceMotion = MediaQuery.of(context).disableAnimations;
    _playMotion();
  }

  void _playMotion() {
    motionController.stop();
    if (reduceMotion) {
      motionController.value = 1;
    } else {
      motionController.repeat(count: 2);
    }
  }

  void _schedulePlayback() {
    playbackTimer?.cancel();
    if (page == pageTitles.length - 1) return;
    playbackTimer = Timer(const Duration(milliseconds: 3400), () {
      if (!mounted || !pager.hasClients || busy) return;
      pager.nextPage(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _pageLabel(int index) => switch (index) {
    0 => '左右轻扫分页浏览，双击或双指放大照片',
    1 => '上滑将照片加入待删除队列，之后仍可改为保留',
    2 => '下滑退出当前照片并返回当前相册列表，当前设置为${widget.downAction.label}',
    3 => '进入待删除队列，选择照片后批量删除',
    _ => '授权开始使用，建议选择完整照片访问权限，照片只在本机处理',
  };

  Widget _photoCard({
    Key? key,
    String asset = 'assets/tutorial-portrait.jpg',
    Alignment alignment = Alignment.center,
    double width = 142,
    double height = 170,
  }) => Container(
    key: key,
    width: width,
    height: height,
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1F000000),
          blurRadius: 22,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(19),
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        alignment: alignment,
        cacheWidth: 480,
        excludeFromSemantics: true,
      ),
    ),
  );

  Widget _motionPill({
    required String label,
    required IconData icon,
    required Color color,
    double opacity = 1,
  }) => Opacity(
    opacity: opacity,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xEFFFFFFF),
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _permissionChoice(
    String label, {
    Key? key,
    bool destructive = false,
    bool highlighted = false,
  }) => Container(
    key: key,
    width: double.infinity,
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: highlighted ? const Color(0x1F007AFF) : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (highlighted) ...[
          const Icon(Icons.check_circle_rounded, color: _systemBlue, size: 14),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: TextStyle(
            color: destructive ? _systemRed : _systemBlue,
            fontSize: 12,
            height: 1.1,
            fontWeight: highlighted ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _tutorialThumb(
    String asset, {
    Key? key,
    double width = 58,
    double height = 52,
    bool selected = false,
  }) => Container(
    key: key,
    width: width,
    height: height,
    padding: EdgeInsets.all(selected ? 2 : 0),
    decoration: BoxDecoration(
      color: selected ? _systemBlue : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(selected ? 9 : 11),
      child: Image.asset(asset, fit: BoxFit.cover, cacheWidth: 240),
    ),
  );

  Widget _queueThumb(String asset, {required bool selected}) => Expanded(
    child: AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(asset, fit: BoxFit.cover, cacheWidth: 240),
            if (selected)
              const Positioned(
                right: 5,
                top: 5,
                child: Icon(
                  Icons.check_circle_rounded,
                  color: _systemBlue,
                  size: 18,
                  shadows: [Shadow(color: Colors.white, blurRadius: 4)],
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _motionScene(int index) => AnimatedBuilder(
    animation: motionController,
    builder: (context, _) {
      final phase = motionController.value;
      double segment(double start, double end) =>
          ((phase - start) / (end - start)).clamp(0.0, 1.0);
      final browseProgress = phase < 0.5
          ? Curves.easeInOutCubic.transform(segment(0.08, 0.38))
          : 1 - Curves.easeInOutCubic.transform(segment(0.62, 0.92));
      final actionProgress = Curves.easeOutCubic.transform(segment(0.12, 0.68));
      final confirmationProgress = Curves.easeOut.transform(
        segment(0.58, 0.76),
      );
      final pulse = 1 - (2 * phase - 1).abs();
      final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
      return Container(
        key: ValueKey('onboarding-motion-scene-${index + 1}'),
        width: double.infinity,
        height: 258,
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(32),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (index == 0) ...[
              Positioned(
                left: 36,
                right: 36,
                top: 14,
                height: 148,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Color(0xFF111111)),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Stack(
                        fit: StackFit.expand,
                        children: [
                          Transform.translate(
                            key: const ValueKey('onboarding-motion-target-1'),
                            offset: Offset(
                              -constraints.maxWidth * browseProgress,
                              0,
                            ),
                            child: Image.asset(
                              'assets/tutorial-portrait.jpg',
                              key: const ValueKey(
                                'onboarding-browse-photo-top',
                              ),
                              fit: BoxFit.cover,
                              cacheWidth: 560,
                            ),
                          ),
                          Transform.translate(
                            key: const ValueKey(
                              'onboarding-browse-incoming-photo',
                            ),
                            offset: Offset(
                              constraints.maxWidth * (1 - browseProgress),
                              0,
                            ),
                            child: Image.asset(
                              'assets/tutorial-landscape.jpg',
                              fit: BoxFit.cover,
                              cacheWidth: 560,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 170,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _tutorialThumb(
                      'assets/tutorial-portrait.jpg',
                      key: const ValueKey('onboarding-browse-photo-left'),
                      width: 46,
                      height: 34,
                      selected: browseProgress < 0.5,
                    ),
                    const SizedBox(width: 5),
                    _tutorialThumb(
                      'assets/tutorial-landscape.jpg',
                      width: 46,
                      height: 34,
                      selected: browseProgress >= 0.5,
                    ),
                    const SizedBox(width: 5),
                    _tutorialThumb(
                      'assets/tutorial-still-life.jpg',
                      key: const ValueKey('onboarding-browse-photo-right'),
                      width: 46,
                      height: 34,
                    ),
                  ],
                ),
              ),
            ],
            if (index == 1) ...[
              Transform.scale(
                scale: 0.98 + 0.02 * actionProgress,
                child: Opacity(
                  opacity: actionProgress,
                  child: _photoCard(
                    key: const ValueKey('onboarding-delete-next-photo'),
                    asset: 'assets/tutorial-portrait.jpg',
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 18,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Transform.scale(
                      key: const ValueKey('onboarding-delete-target'),
                      scale: 0.9 + 0.16 * pulse,
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFE9E7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: _systemRed,
                          size: 28,
                        ),
                      ),
                    ),
                    if (confirmationProgress > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Opacity(
                          opacity: confirmationProgress,
                          child: Container(
                            width: 21,
                            height: 21,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: _systemRed,
                              shape: BoxShape.circle,
                            ),
                            child: const Text(
                              '1',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Transform.translate(
                key: const ValueKey('onboarding-motion-target-2'),
                offset: Offset(105 * actionProgress, 28 - 88 * actionProgress),
                child: Transform.scale(
                  scale: 1 - 0.82 * actionProgress,
                  child: Opacity(
                    opacity: 1 - actionProgress,
                    child: _photoCard(asset: 'assets/tutorial-landscape.jpg'),
                  ),
                ),
              ),
              Positioned(
                top: 78,
                right: 16,
                child: _motionPill(
                  label: '已加入待删除队列',
                  icon: Icons.check_circle_rounded,
                  color: _systemRed,
                  opacity: confirmationProgress,
                ),
              ),
            ],
            if (index == 2) ...[
              Positioned(
                left: 24,
                right: 24,
                top: 14,
                bottom: 48,
                child: Container(
                  key: const ValueKey('onboarding-return-album-target'),
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(color: Color(0x14000000), blurRadius: 16),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: _systemBlue,
                            size: 13,
                          ),
                          SizedBox(width: 5),
                          Text(
                            '当前相册',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Spacer(),
                          Text(
                            '18 张',
                            style: TextStyle(
                              color: _secondaryLabel,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: GridView.count(
                          key: const ValueKey('onboarding-current-album-grid'),
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 3,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                          children:
                              [
                                    'assets/tutorial-portrait.jpg',
                                    'assets/tutorial-landscape.jpg',
                                    'assets/tutorial-still-life.jpg',
                                    'assets/tutorial-landscape.jpg',
                                    'assets/tutorial-still-life.jpg',
                                    'assets/tutorial-portrait.jpg',
                                  ]
                                  .map(
                                    (asset) => ClipRRect(
                                      borderRadius: BorderRadius.circular(7),
                                      child: Image.asset(
                                        asset,
                                        fit: BoxFit.cover,
                                        cacheWidth: 180,
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Transform.translate(
                key: const ValueKey('onboarding-motion-target-3'),
                offset: Offset(0, -22 + 118 * actionProgress),
                child: Transform.scale(
                  scale: 1 - 0.48 * actionProgress,
                  child: Opacity(
                    opacity: 1 - actionProgress,
                    child: _photoCard(
                      asset: 'assets/tutorial-still-life.jpg',
                      width: 124,
                      height: 148,
                    ),
                  ),
                ),
              ),
            ],
            if (index == 3) ...[
              Positioned(
                left: 20,
                right: 20,
                top: 12,
                bottom: 48,
                child: Container(
                  key: const ValueKey('onboarding-motion-target-4'),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(color: Color(0x14000000), blurRadius: 16),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          Text(
                            '待删除队列',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Spacer(),
                          Text(
                            '全选',
                            style: TextStyle(
                              color: _systemBlue,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        key: const ValueKey('onboarding-queue-grid'),
                        children: [
                          _queueThumb(
                            'assets/tutorial-portrait.jpg',
                            selected: actionProgress > 0.3,
                          ),
                          const SizedBox(width: 5),
                          _queueThumb(
                            'assets/tutorial-landscape.jpg',
                            selected: actionProgress > 0.45,
                          ),
                          const SizedBox(width: 5),
                          _queueThumb(
                            'assets/tutorial-still-life.jpg',
                            selected: actionProgress > 0.6,
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Transform.scale(
                        scale: 0.96 + 0.04 * confirmationProgress,
                        child: Container(
                          key: const ValueKey('onboarding-batch-delete'),
                          width: double.infinity,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              const Color(0xFFFFE9E7),
                              _systemRed,
                              confirmationProgress,
                            ),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Text(
                            '删除 3 项',
                            style: TextStyle(
                              color: Color.lerp(
                                _systemRed,
                                Colors.white,
                                confirmationProgress,
                              ),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (index == 4)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _tutorialThumb(
                            'assets/tutorial-portrait.jpg',
                            key: const ValueKey(
                              'onboarding-permission-photo-1',
                            ),
                          ),
                          const SizedBox(width: 7),
                          _tutorialThumb(
                            'assets/tutorial-landscape.jpg',
                            key: const ValueKey(
                              'onboarding-permission-photo-2',
                            ),
                          ),
                          const SizedBox(width: 7),
                          _tutorialThumb(
                            'assets/tutorial-still-life.jpg',
                            key: const ValueKey(
                              'onboarding-permission-photo-3',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Transform.scale(
                        key: const ValueKey('onboarding-motion-target-5'),
                        scale: 0.97 + 0.03 * pulse,
                        child: Container(
                          width: 242,
                          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                          decoration: BoxDecoration(
                            color: const Color(0xF7FFFFFF),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x1A000000),
                                blurRadius: 16,
                                offset: Offset(0, 7),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Text(
                                isIOS ? '允许“相册清理”访问你的照片吗？' : '允许相册清理访问照片和视频吗？',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: _primaryLabel,
                                  fontSize: 13,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                '照片只在本机整理',
                                style: TextStyle(
                                  color: _secondaryLabel,
                                  fontSize: 10,
                                ),
                              ),
                              _permissionChoice(
                                isIOS ? '允许完全访问' : '允许全部',
                                key: const ValueKey(
                                  'onboarding-permission-allow-all',
                                ),
                                highlighted: true,
                              ),
                              _permissionChoice(isIOS ? '选择照片…' : '选择照片和视频'),
                              _permissionChoice('不允许', destructive: true),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (index < 4)
              Positioned(
                bottom: 8,
                child: _motionPill(
                  label: switch (index) {
                    0 => '左右轻扫 · 双击放大',
                    1 => '上滑加入队列',
                    2 => '下滑返回当前相册',
                    _ => '进入队列 · 选择 · 批量删除',
                  },
                  icon: switch (index) {
                    0 => Icons.swipe_rounded,
                    1 => Icons.delete_outline_rounded,
                    2 => Icons.photo_library_outlined,
                    _ => Icons.delete_sweep_outlined,
                  },
                  color: index == 1 || index == 3 ? _systemRed : _systemBlue,
                  opacity: index == 0
                      ? 0.72 + 0.28 * pulse
                      : 0.4 + 0.6 * actionProgress,
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _tutorialPage(int index) => Semantics(
    label: _pageLabel(index),
    container: true,
    excludeSemantics: true,
    child: Padding(
      key: ValueKey('onboarding-page-${index + 1}'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _motionScene(index),
          const SizedBox(height: 28),
          Text(
            pageTitles[index],
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _primaryLabel,
              fontSize: 28,
              height: 1.1,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            pageDescriptions[index],
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _secondaryLabel,
              fontSize: 17,
              height: 1.42,
            ),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    playbackTimer?.cancel();
    motionController.dispose();
    pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _systemBackground,
    extendBodyBehindAppBar: Navigator.canPop(context),
    appBar: Navigator.canPop(context)
        ? const _UnifiedAppBar(title: '使用教程')
        : null,
    body: Stack(
      fit: StackFit.expand,
      children: [
        if (!Navigator.canPop(context))
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 84,
            child: _SystemTopGradient(key: Key('page-top-gradient')),
          ),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.only(top: Navigator.canPop(context) ? 60 : 0),
            child: Column(
              children: [
                Padding(
                  key: const Key('onboarding-progress'),
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: List.generate(
                          pageTitles.length,
                          (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 7),
                            decoration: BoxDecoration(
                              color: index == page
                                  ? _systemBlue
                                  : const Color(0x33787880),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${page + 1} / ${pageTitles.length}',
                        key: const Key('onboarding-page-indicator'),
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    key: const Key('onboarding-pager'),
                    controller: pager,
                    itemCount: pageTitles.length,
                    onPageChanged: (value) {
                      setState(() => page = value);
                      _playMotion();
                      _schedulePlayback();
                    },
                    itemBuilder: (context, index) => _tutorialPage(index),
                  ),
                ),
                Padding(
                  key: const Key('onboarding-navigation'),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (page > 0)
                        FilledButton.tonal(
                          key: const Key('onboarding-previous'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(108, 48),
                            backgroundColor: const Color(0x14007AFF),
                            foregroundColor: _systemBlue,
                          ),
                          onPressed: () => pager.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                          ),
                          child: const Text('返回'),
                        ),
                      if (page > 0) const SizedBox(width: 12),
                      FilledButton(
                        key: const Key('onboarding-next'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(108, 48),
                        ),
                        onPressed: busy
                            ? null
                            : () async {
                                if (page < pageTitles.length - 1) {
                                  pager.nextPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeOutCubic,
                                  );
                                } else {
                                  playbackTimer?.cancel();
                                  setState(() => busy = true);
                                  try {
                                    await widget.onDone();
                                  } finally {
                                    if (mounted) setState(() => busy = false);
                                  }
                                }
                              },
                        child: Text(
                          page == pageTitles.length - 1 ? '继续授权' : '继续',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class PermissionScreen extends StatelessWidget {
  const PermissionScreen(this.app, {super.key});
  final CleanerState app;

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: const _UnifiedAppBar(title: '照片访问权限'),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 60, 28, 28),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5F2FF),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.photo_library_outlined,
                  color: _systemBlue,
                  size: 42,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                '允许访问照片',
                style: TextStyle(
                  color: _primaryLabel,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '需要照片访问权限才能整理相册。你也可以只选择部分照片。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _secondaryLabel,
                  fontSize: 17,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: app.requestPermission,
                  child: const Text('继续'),
                ),
              ),
              TextButton(
                onPressed: app.managePermission,
                child: const Text('前往系统设置'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen(this.app, {super.key});
  final CleanerState app;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;
  Future<List<SystemAlbumSummary>>? systemAlbums;
  late Future<List<SystemCategorySummary>> systemCategories;
  late Future<List<MediaRecord>> allMediaCover;
  late Future<List<int>> localCategoryCounts;
  late Future<SimilarPhotoStatus> similarPhotoStatus;
  late int observedScanRevision;
  MediaStorageSummary? storage;
  bool storageLoading = false;
  int storageProcessed = 0;
  int storageTotal = 0;

  CleanerState get app => widget.app;

  @override
  void initState() {
    super.initState();
    storage = app.storageSummary;
    observedScanRevision = app.scanRevision;
    systemCategories = Platform.isIOS
        ? _loadSystemCategoriesAfterFirstFrame()
        : Future.value(const []);
    allMediaCover = _loadAllMediaCover();
    localCategoryCounts = _loadLocalCategoryCounts();
    similarPhotoStatus = _loadSimilarPhotoStatus();
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (observedScanRevision == app.scanRevision) return;
    observedScanRevision = app.scanRevision;
    app.invalidateStorageSummary();
    storage = null;
    allMediaCover = _loadAllMediaCover();
    localCategoryCounts = _loadLocalCategoryCounts();
    similarPhotoStatus = _loadSimilarPhotoStatus();
    if (systemAlbums != null) systemAlbums = _loadVisibleSystemAlbums(app);
    if (Platform.isIOS) systemCategories = _loadVisibleSystemCategories(app);
  }

  Future<List<SystemCategorySummary>>
  _loadSystemCategoriesAfterFirstFrame() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return const [];
    return _loadVisibleSystemCategories(app);
  }

  void _ensureAlbumsLoaded() {
    systemAlbums ??= _loadVisibleSystemAlbums(app);
  }

  Future<List<MediaRecord>> _loadAllMediaCover() async => (await Future.wait([
    for (var index = 0; index < 3; index++) app.store.at(Scope.all, index),
  ])).whereType<MediaRecord>().toList();

  Future<List<int>> _loadLocalCategoryCounts() => Future.wait([
    app.store.count(Scope.videos),
    app.store.count(Scope.screenshots),
    app.store.count(Scope.selfies),
    app.store.count(Scope.live),
  ]);

  Future<SimilarPhotoStatus> _loadSimilarPhotoStatus() =>
      app.media.cachedSimilarPhotoStatus(app.store);

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) {
      setState(() {
        allMediaCover = _loadAllMediaCover();
        similarPhotoStatus = _loadSimilarPhotoStatus();
        if (systemAlbums != null) systemAlbums = _loadVisibleSystemAlbums(app);
        if (Platform.isIOS) {
          systemCategories = _loadVisibleSystemCategories(app);
        }
      });
    }
  }

  Future<void> _calculateStorage() async {
    if (storageLoading || storage != null) return;
    if (app.storageSummary case final cached?) {
      setState(() => storage = cached);
      return;
    }
    setState(() => storageLoading = true);
    try {
      final result = await app.loadStorageSummary((processed, total) {
        if (mounted) {
          setState(() {
            storageProcessed = processed;
            storageTotal = total;
          });
        }
      });
      if (mounted) setState(() => storage = result);
    } finally {
      if (mounted) setState(() => storageLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    await app.refresh();
    if (!mounted) return;
    storageProcessed = 0;
    storageTotal = 0;
    if (tab == 2) await _calculateStorage();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    final gb = bytes / (1024 * 1024 * 1024);
    if (gb >= 1) return '${gb.toStringAsFixed(gb >= 10 ? 1 : 2)} GB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }

  Widget _sectionTitle(
    String title, {
    String? subtitle,
    double topPadding = 22,
  }) => Padding(
    key: ValueKey('section-$title'),
    padding: EdgeInsets.fromLTRB(0, topPadding, 0, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _primaryLabel,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle,
              style: const TextStyle(color: _secondaryLabel),
            ),
          ),
      ],
    ),
  );

  Widget _brandHeader() => Row(
    key: const Key('home-brand'),
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Image.asset(
          'assets/app-logo.png',
          key: const Key('home-brand-logo'),
          width: 40,
          height: 40,
        ),
      ),
      const SizedBox(width: 10),
      const Expanded(
        child: Text(
          '相册删除',
          style: TextStyle(
            color: _primaryLabel,
            fontSize: 34,
            height: 1.08,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        ),
      ),
      _GlassIconButton(
        buttonKey: const Key('home-tutorial'),
        tooltip: '使用教程',
        icon: Icons.help_outline_rounded,
        foregroundColor: _systemBlue,
        diameter: 44,
        iconSize: 24,
        onPressed: () => _open(
          OnboardingScreen(
            downAction: app.downAction,
            onDone: () async {
              if (mounted) Navigator.pop(context);
            },
          ),
        ),
      ),
    ],
  );

  Widget _scopeTile(
    Scope scope,
    IconData icon, {
    int? knownCount,
    String? title,
  }) => FutureBuilder<int>(
    future: knownCount == null
        ? app.store.count(scope)
        : Future.value(knownCount),
    builder: (context, count) => _compactCategoryTile(
      key: ValueKey('scope-${scope.key}'),
      icon: icon,
      label: title ?? scope.label,
      count: count.data,
      onTap: () => _open(ScopeScreen(app, scope)),
    ),
  );

  Widget _tileGrid(List<Widget> children) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: ColoredBox(
      color: _secondarySystemBackground,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const Divider(indent: 56),
            children[index],
          ],
        ],
      ),
    ),
  );

  Widget _queueCard() => FutureBuilder<List<Map<String, Object?>>>(
    future: app.store.queue(),
    builder: (context, queue) => Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 12,
        ),
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFEAF0FF),
          child: Icon(Icons.delete_outline, color: _systemBlue),
        ),
        title: const Text(
          '待删除队列',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          queue.hasData
              ? '${queue.data!.length} 项待复核 · 删除前会再次确认'
              : '先复核，再交给系统处理',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(QueueScreen(app)),
      ),
    ),
  );

  Widget _pendingQueueCard() => FutureBuilder<int>(
    future: app.store.count(Scope.all, pendingOnly: true),
    builder: (context, count) => Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 12,
        ),
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFFFF5E8),
          child: Icon(Icons.schedule_outlined, color: Color(0xFFC76A00)),
        ),
        title: const Text(
          '待定队列',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(count.hasData ? '${count.data} 项待稍后决定' : '正在读取'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            _open(ScopeScreen(app, Scope.all, initialPendingOnly: true)),
      ),
    ),
  );

  Widget _heroIntro() => SizedBox(
    height: 142,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final artWidth = (constraints.maxWidth * 0.43)
            .clamp(136.0, 166.0)
            .toDouble();
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 18,
              width: constraints.maxWidth - artWidth - 8,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '清理重复和无用照片\n让相册更清爽',
                    style: TextStyle(
                      color: Color(0xFF111A35),
                      fontSize: 17,
                      height: 1.22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: 9),
                  Text(
                    '从上次停下的位置继续整理',
                    style: TextStyle(
                      color: Color(0xFF6E7892),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 12,
              top: -2,
              width: artWidth,
              height: 116,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F23469A),
                      blurRadius: 18,
                      offset: Offset(0, 7),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/home-hero-landscape.jpg',
                    key: const Key('home-hero-landscape'),
                    fit: BoxFit.cover,
                    alignment: const Alignment(-0.25, -0.08),
                    cacheWidth: 720,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _reviewHero() => FutureBuilder<ReviewProgress?>(
    future: app.store.reviewProgress(Scope.all),
    builder: (context, progressSnapshot) => FutureBuilder<int>(
      future: app.store.count(Scope.all, unreviewedOnly: true),
      builder: (context, countSnapshot) {
        final progress = progressSnapshot.data;
        final hasProgress = progress != null && progress.total > 0;
        final available = countSnapshot.data;
        final total = hasProgress ? progress.total : available;
        final completed = hasProgress
            ? (progress.position + 1).clamp(0, progress.total)
            : 0;
        final ratio = hasProgress ? completed / progress.total : 0.0;
        final percent = (ratio * 100).round();
        final enabled = hasProgress || available != 0;
        return _GlassSurface(
          key: const Key('review-hero-glass'),
          radius: 22,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('review-hero'),
              borderRadius: BorderRadius.circular(22),
              onTap: enabled
                  ? () => _open(ScopeScreen(app, Scope.all, startReview: true))
                  : null,
              child: SizedBox(
                height: 76,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 52,
                              height: 52,
                              child: CircularProgressIndicator(
                                value: ratio,
                                strokeWidth: 4,
                                backgroundColor: const Color(0x99FFFFFF),
                                color: _systemBlue,
                              ),
                            ),
                            Container(
                              width: 42,
                              height: 42,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Color(0xBFFFFFFF),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$percent%',
                                style: const TextStyle(
                                  color: Color(0xFF1557F8),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hasProgress ? '继续整理' : '开始整理',
                              style: const TextStyle(
                                color: _primaryLabel,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              hasProgress
                                  ? '第 $completed / ${progress.total} 项'
                                  : total == null
                                  ? '正在读取相册'
                                  : '当前可整理 $total 项照片与视频',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _secondaryLabel,
                                fontSize: 13,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: enabled
                              ? const Color(0xBFFFFFFF)
                              : const Color(0x66FFFFFF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF3158E6),
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  String _categoryLabel(SystemCategorySummary category) => systemCategoryLabel(
    category.kind,
    providerLabel: category.label,
    languageCode: ui.PlatformDispatcher.instance.locale.languageCode,
  );

  IconData _categoryIcon(SystemCategoryKind kind) => switch (kind) {
    SystemCategoryKind.generic => Icons.auto_awesome_outlined,
    SystemCategoryKind.panoramas => Icons.panorama_horizontal_outlined,
    SystemCategoryKind.videos => Icons.play_circle_outline,
    SystemCategoryKind.favorites => Icons.favorite_border_rounded,
    SystemCategoryKind.timelapses => Icons.timelapse_rounded,
    SystemCategoryKind.recentlyAdded => Icons.update_rounded,
    SystemCategoryKind.bursts => Icons.burst_mode_outlined,
    SystemCategoryKind.slowMotion => Icons.slow_motion_video_rounded,
    SystemCategoryKind.screenshots => Icons.screenshot_outlined,
    SystemCategoryKind.live => Icons.motion_photos_on_outlined,
    SystemCategoryKind.selfies => Icons.face_outlined,
    SystemCategoryKind.depthEffect => Icons.blur_on_rounded,
    SystemCategoryKind.animated => Icons.animation_rounded,
    SystemCategoryKind.longExposures => Icons.shutter_speed_rounded,
    SystemCategoryKind.raw => Icons.raw_on_outlined,
    SystemCategoryKind.cinematic => Icons.movie_filter_outlined,
    SystemCategoryKind.spatial => Icons.view_in_ar_outlined,
    SystemCategoryKind.screenRecordings => Icons.screen_share_outlined,
    SystemCategoryKind.receipts => Icons.receipt_long_outlined,
    SystemCategoryKind.handwriting => Icons.draw_outlined,
    SystemCategoryKind.illustrations => Icons.brush_outlined,
    SystemCategoryKind.qrCodes => Icons.qr_code_rounded,
  };

  Widget _systemCategoryTile(SystemCategorySummary category) {
    final label = _categoryLabel(category);
    return _compactCategoryTile(
      key: ValueKey('category-${category.kind.name}'),
      icon: _categoryIcon(category.kind),
      label: label,
      count: category.count,
      onTap: () => _open(
        SystemAlbumScreen(
          app,
          SystemAlbumSummary(
            path: category.path,
            count: category.count,
            coverId: category.coverId,
            group: SystemAlbumGroup.smart,
          ),
          title: label,
        ),
      ),
    );
  }

  Widget _compactCategoryTile({
    required Key key,
    required IconData icon,
    required String label,
    required int? count,
    required VoidCallback onTap,
    String? countText,
    Color accent = _systemBlue,
  }) => SizedBox(
    height: 58,
    child: InkWell(
      key: key,
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        color: _secondarySystemBackground,
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _primaryLabel,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Text(
              countText ?? (count == null ? '读取中' : '$count'),
              style: const TextStyle(color: _secondaryLabel, fontSize: 15),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              color: _tertiaryLabel,
              size: 20,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _allMediaCoverCell(MediaRecord item, int index) => ClipRect(
    child: ColoredBox(
      key: ValueKey('all-media-cover-cell-$index'),
      color: Colors.white,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MediaThumb(
            app.media,
            item.id,
            key: ValueKey('all-media-cover-${item.id}'),
            width: 520,
            height: 260,
          ),
          if (item.type == 2)
            Center(
              child: Container(
                key: ValueKey('all-media-cover-video-marker-${item.id}'),
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: Color(0x99000000),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _allMediaMosaic(List<MediaRecord> items) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 4.0;
      final sideWidth = constraints.maxWidth * 0.36;
      final mainWidth = constraints.maxWidth - sideWidth - gap;
      final sideHeight = (constraints.maxHeight - gap) / 2;
      Widget cell(int index) => index < items.length
          ? _allMediaCoverCell(items[index], index)
          : const ColoredBox(
              color: Color(0xFFEAF2FF),
              child: Icon(
                Icons.image_outlined,
                color: Color(0xFFAAC3F8),
                size: 24,
              ),
            );
      return Stack(
        key: const Key('all-media-art-mosaic'),
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: mainWidth,
            child: cell(0),
          ),
          Positioned(
            right: 0,
            top: 0,
            width: sideWidth,
            height: sideHeight,
            child: cell(1),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            width: sideWidth,
            height: sideHeight,
            child: cell(2),
          ),
        ],
      );
    },
  );

  Widget _allMediaCategoryTile() => FutureBuilder<int>(
    key: const Key('home-all-media-card'),
    future: app.store.count(Scope.all),
    builder: (context, count) => Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('category-all'),
        borderRadius: BorderRadius.circular(22),
        onTap: () => _open(ScopeScreen(app, Scope.all)),
        child: Ink(
          height: 168,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xEFFFFFFF),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFDCE5F7)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final coverWidth = (constraints.maxWidth * 0.53)
                  .clamp(148.0, 226.0)
                  .toDouble();
              return Row(
                children: [
                  SizedBox(
                    width: coverWidth,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: FutureBuilder<List<MediaRecord>>(
                        future: allMediaCover,
                        builder: (context, snapshot) =>
                            _allMediaMosaic(snapshot.data ?? const []),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F1FF),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(
                            Icons.photo_library_outlined,
                            color: Color(0xFF4D51EE),
                            size: 23,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '全部照片与视频',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFF111A35),
                            fontSize: 16,
                            height: 1.16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          '完整浏览相册内容',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFF6E7892),
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                count.hasData ? '${count.data}' : '读取中',
                                style: const TextStyle(
                                  color: Color(0xFF245BF0),
                                  fontSize: 30,
                                  height: 1,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF2F5FD),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.arrow_forward_rounded,
                                color: Color(0xFF245BF0),
                                size: 21,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _similarCategoryTile() => FutureBuilder<SimilarPhotoStatus>(
    future: similarPhotoStatus,
    builder: (context, snapshot) {
      final status = snapshot.data;
      final countText = status == null
          ? '读取中'
          : !status.hasAnalysis
          ? '点击分析'
          : status.needsUpdate
          ? '可更新'
          : status.photoCount == 0
          ? '未发现'
          : '${status.groupCount} 组 · ${status.photoCount} 张';
      return _compactCategoryTile(
        key: const ValueKey('category-similar'),
        icon: Icons.auto_awesome_mosaic_outlined,
        label: '相似照片',
        count: status?.photoCount,
        countText: countText,
        accent: const Color(0xFF119C9A),
        onTap: () => _open(SimilarPhotosScreen(app)),
      );
    },
  );

  Widget _compactCategoryList(List<Widget> children) {
    if (children.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) rows.add(const Divider(indent: 56));
      rows.add(children[index]);
    }
    return ClipRRect(
      key: const Key('category-grid'),
      borderRadius: BorderRadius.circular(14),
      child: ColoredBox(
        color: _secondarySystemBackground,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }

  Widget _categoryGrid() {
    if (!Platform.isIOS) {
      const categories = [
        (Scope.videos, Icons.videocam_outlined, Color(0xFF078CA6)),
        (Scope.screenshots, Icons.screenshot_outlined, Color(0xFF6C4BEF)),
        (Scope.selfies, Icons.face_outlined, Color(0xFFE8863A)),
        (Scope.live, Icons.motion_photos_on_outlined, Color(0xFF3978DD)),
      ];
      return FutureBuilder<List<int>>(
        future: localCategoryCounts,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final counts = snapshot.data!;
          return _compactCategoryList([
            for (var index = 0; index < categories.length; index++)
              if (counts[index] > 0)
                _compactCategoryTile(
                  key: ValueKey('category-${categories[index].$1.key}'),
                  icon: categories[index].$2,
                  label: categories[index].$1.label,
                  count: counts[index],
                  accent: categories[index].$3,
                  onTap: () => _open(ScopeScreen(app, categories[index].$1)),
                ),
            _similarCategoryTile(),
          ]);
        },
      );
    }
    return FutureBuilder<List<SystemCategorySummary>>(
      future: systemCategories,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final categories = snapshot.data ?? const <SystemCategorySummary>[];
        return _compactCategoryList([
          ...categories.map(_systemCategoryTile),
          _similarCategoryTile(),
        ]);
      },
    );
  }

  Widget _homeHeader() => Stack(
    children: [
      Positioned.fill(
        child: Image.asset(
          'assets/home-header-background.png',
          key: const Key('home-header-background'),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          excludeFromSemantics: true,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          children: [_heroIntro(), const SizedBox(height: 4), _reviewHero()],
        ),
      ),
    ],
  );

  Widget _home() => ListView(
    key: const Key('home-scroll'),
    padding: const EdgeInsets.only(top: 4, bottom: 112),
    children: [
      Padding(
        key: const Key('home-root-header'),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _brandHeader(),
      ),
      _homeHeader(),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (app.scanFailed)
              Card(
                child: ListTile(
                  title: const Text('相册读取失败'),
                  trailing: TextButton(
                    onPressed: app.refresh,
                    child: const Text('重试'),
                  ),
                ),
              ),
            if (app.permissionState == PermissionState.limited)
              Card(
                child: ListTile(
                  title: const Text('当前仅整理已授权的媒体'),
                  trailing: TextButton(
                    onPressed: app.managePermission,
                    child: const Text('扩充范围'),
                  ),
                ),
              ),
            _sectionTitle('照片总览', topPadding: 26),
            _allMediaCategoryTile(),
            _sectionTitle('分类整理'),
            _categoryGrid(),
            if (Platform.isAndroid)
              const Padding(
                padding: EdgeInsets.only(top: 18),
                child: Text(
                  '自拍和动态照片在 Android 上没有统一的可靠标记，可在“全部”中查看。',
                  style: TextStyle(color: _secondaryLabel, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _albumCard(SystemAlbumSummary album) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () => _open(SystemAlbumScreen(app, album)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 1.2,
            child: album.coverId == null
                ? const ColoredBox(
                    color: Color(0xFFEAF0FF),
                    child: Icon(
                      Icons.photo_library_outlined,
                      color: _systemBlue,
                    ),
                  )
                : MediaThumb(app.media, album.coverId!),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          album.path.name.trim().isEmpty ? '未命名相册' : album.path.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(
          '${album.count} 项',
          style: const TextStyle(color: _secondaryLabel, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _albumGrid(
    String title,
    List<SystemAlbumSummary> albums, {
    Key? key,
    double topPadding = 22,
  }) {
    if (albums.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title, topPadding: topPadding),
        GridView.builder(
          key: key,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: albums.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _albumGridColumnCount(
              MediaQuery.sizeOf(context).width,
            ),
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
            childAspectRatio: 0.84,
          ),
          itemBuilder: (context, index) => _albumCard(albums[index]),
        ),
      ],
    );
  }

  Widget _albumAllMediaHero() => FutureBuilder<int>(
    future: app.store.count(Scope.all),
    builder: (context, count) => Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('album-all-media-hero'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(ScopeScreen(app, Scope.all)),
        child: Ink(
          height: 176,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _secondarySystemBackground,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: FutureBuilder<List<MediaRecord>>(
                    future: allMediaCover,
                    builder: (context, snapshot) =>
                        _allMediaMosaic(snapshot.data ?? const []),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.photo_library_outlined,
                      color: _systemBlue,
                      size: 25,
                    ),
                    const Spacer(),
                    const Text(
                      '全部照片与视频',
                      maxLines: 2,
                      style: TextStyle(
                        color: _primaryLabel,
                        fontSize: 17,
                        height: 1.12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      count.hasData ? '${count.data} 项 · 打开图库' : '正在读取图库',
                      style: const TextStyle(
                        color: _secondaryLabel,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: _systemBlue,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _albumCategories() => FutureBuilder<List<SystemAlbumSummary>>(
    future: systemAlbums,
    builder: (context, snapshot) {
      final albums = snapshot.data ?? const <SystemAlbumSummary>[];
      final personal = albums
          .where((album) => album.group == SystemAlbumGroup.album)
          .toList();
      final people = albums
          .where((album) => album.group == SystemAlbumGroup.people)
          .toList();
      final smart = albums
          .where((album) => album.group == SystemAlbumGroup.smart)
          .toList();
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 112),
        children: [
          const Text(
            '相册',
            key: Key('albums-large-title'),
            style: TextStyle(
              color: _primaryLabel,
              fontSize: 34,
              height: 1.08,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 22),
          _albumAllMediaHero(),
          if (snapshot.connectionState == ConnectionState.waiting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: Center(child: CircularProgressIndicator()),
            ),
          _albumGrid('手机相册', personal, key: const Key('system-album-grid')),
          _albumGrid('人物', people),
          _albumGrid('系统分类', smart, topPadding: 6),
          if (!Platform.isIOS) ...[
            _sectionTitle('媒体类型'),
            _tileGrid([
              _scopeTile(Scope.screenshots, Icons.screenshot_outlined),
              _scopeTile(Scope.videos, Icons.play_circle_outline),
            ]),
          ],
        ],
      );
    },
  );

  Widget _albums() {
    _ensureAlbumsLoaded();
    return _albumCategories();
  }

  List<(String, int?, Color)> _storageMetrics() {
    final metrics = <(String, int?, Color)>[
      ('照片', storage?.photoBytes, _systemBlue),
      ('视频', storage?.videoBytes, const Color(0xFFFF9B37)),
      ('截图', storage?.screenshotBytes, const Color(0xFF7C4DFF)),
      ('实况', storage?.liveBytes, const Color(0xFF2F8A67)),
    ];
    metrics.sort((left, right) => (right.$2 ?? 0).compareTo(left.$2 ?? 0));
    return metrics;
  }

  Widget _storageOverview() {
    final metrics = _storageMetrics();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '相册空间',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Text(
              storage != null
                  ? _formatBytes(storage!.totalBytes)
                  : storageLoading
                  ? '正在计算授权媒体…'
                  : '等待计算',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            if (storageLoading)
              LinearProgressIndicator(
                value: storageTotal == 0
                    ? null
                    : storageProcessed / storageTotal,
                borderRadius: BorderRadius.circular(8),
              )
            else if (storage != null && storage!.totalBytes > 0)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    for (final metric in metrics)
                      if ((metric.$2 ?? 0) > 0)
                        Expanded(
                          flex: metric.$2!,
                          child: ColoredBox(
                            color: metric.$3,
                            child: const SizedBox(height: 14),
                          ),
                        ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _storageMetric(
                    metrics[0].$1,
                    metrics[0].$2,
                    metrics[0].$3,
                  ),
                ),
                const SizedBox(width: 22),
                Expanded(
                  child: _storageMetric(
                    metrics[1].$1,
                    metrics[1].$2,
                    metrics[1].$3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _storageMetric(
                    metrics[2].$1,
                    metrics[2].$2,
                    metrics[2].$3,
                  ),
                ),
                const SizedBox(width: 22),
                Expanded(
                  child: _storageMetric(
                    metrics[3].$1,
                    metrics[3].$2,
                    metrics[3].$3,
                  ),
                ),
              ],
            ),
            if (storage?.unknownItems case final unknown? when unknown > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '$unknown 项暂时无法取得大小，以上为当前授权范围的估算值。',
                  style: const TextStyle(color: _secondaryLabel, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _storageMetric(String label, int? bytes, Color color) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 7),
      Text(label, style: const TextStyle(color: Color(0xFF565D69))),
      const Spacer(),
      Text(
        bytes == null ? '计算中' : _formatBytes(bytes),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ],
  );

  Widget _more() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 112),
    children: [
      const Text(
        '我的',
        key: Key('profile-large-title'),
        style: TextStyle(
          color: _primaryLabel,
          fontSize: 34,
          height: 1.08,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
      ),
      const SizedBox(height: 22),
      _storageOverview(),
      _sectionTitle('待处理'),
      _queueCard(),
      if (app.downAction == DownSwipeAction.pending) ...[
        const SizedBox(height: 12),
        _pendingQueueCard(),
      ],
      _sectionTitle('偏好与帮助'),
      Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.swipe_down_outlined),
              title: const Text('下滑动作与设置'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(SettingsScreen(app)),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('使用教程'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(
                OnboardingScreen(
                  downAction: app.downAction,
                  onDone: () async {
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('管理照片权限'),
              trailing: const Icon(Icons.chevron_right),
              onTap: app.managePermission,
            ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 20),
        child: Text(
          '照片仅在本机读取。待删除标记不会立即删除媒体。',
          textAlign: TextAlign.center,
          style: TextStyle(color: _secondaryLabel, fontSize: 12),
        ),
      ),
    ],
  );

  Widget _tabBody() => AnimatedSwitcher(
    duration: const Duration(milliseconds: 240),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.035, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: RefreshIndicator(
      key: ValueKey(tab),
      onRefresh: _refreshAll,
      child: switch (tab) {
        0 => _home(),
        1 => _albums(),
        _ => _more(),
      },
    ),
  );

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
    ),
    child: Scaffold(
      backgroundColor: _systemBackground,
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 84,
            child: _SystemTopGradient(key: Key('page-top-gradient')),
          ),
          SafeArea(bottom: false, child: _tabBody()),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: _GlassSurface(
          key: const Key('home-glass-nav'),
          radius: 30,
          child: Stack(
            children: [
              NavigationBar(
                height: 62,
                selectedIndex: tab,
                onDestinationSelected: (index) {
                  if (index == 1) _ensureAlbumsLoaded();
                  setState(() => tab = index);
                  if (index == 2) _calculateStorage();
                },
                backgroundColor: Colors.transparent,
                elevation: 0,
                destinations: const [
                  NavigationDestination(
                    key: Key('home-tab'),
                    icon: Icon(Icons.photo_library_outlined),
                    selectedIcon: _SelectedNavIcon(Icons.photo_library_rounded),
                    label: '首页',
                  ),
                  NavigationDestination(
                    key: Key('albums-tab'),
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: _SelectedNavIcon(Icons.grid_view_rounded),
                    label: '相册',
                  ),
                  NavigationDestination(
                    key: Key('profile-tab'),
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: _SelectedNavIcon(Icons.person_rounded),
                    label: '我的',
                  ),
                ],
              ),
              const Positioned(
                key: Key('home-glass-reflection'),
                left: 24,
                right: 24,
                top: 1,
                height: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0x00FFFFFF),
                        Color(0xFFFFFFFF),
                        Color(0x00FFFFFF),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DragSelectableGrid extends StatefulWidget {
  const _DragSelectableGrid({
    required this.gridKey,
    required this.controller,
    required this.padding,
    required this.crossAxisCount,
    required this.itemCount,
    required this.itemBuilder,
    required this.selectionKeyBuilder,
    required this.enabled,
    required this.busy,
    required this.isSelected,
    required this.onSelectionChanged,
  });

  final Key gridKey;
  final ScrollController controller;
  final EdgeInsets padding;
  final int crossAxisCount;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Key Function(int index) selectionKeyBuilder;
  final bool enabled;
  final bool busy;
  final bool Function(int index) isSelected;
  final ValueChanged<Set<int>> onSelectionChanged;

  @override
  State<_DragSelectableGrid> createState() => _DragSelectableGridState();
}

class _DragSelectableGridState extends State<_DragSelectableGrid> {
  final surfaceKey = GlobalKey();
  int? pointer;
  int? startIndex;
  Offset? startPosition;
  Set<int> selectionBase = {};
  bool dragActive = false;
  bool dragValue = true;
  Timer? autoScrollTimer;
  Offset? dragPosition;

  @override
  void didUpdateWidget(covariant _DragSelectableGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || widget.busy) _resetDrag();
  }

  @override
  void dispose() {
    autoScrollTimer?.cancel();
    super.dispose();
  }

  int? _indexAt(Offset globalPosition) {
    final box = surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(globalPosition);
    final usableWidth = box.size.width - widget.padding.horizontal;
    const spacing = 4.0;
    final extent =
        (usableWidth - spacing * (widget.crossAxisCount - 1)) /
        widget.crossAxisCount;
    final stride = extent + spacing;
    final x = local.dx - widget.padding.left;
    if (x < 0 || x >= usableWidth) return null;
    final column = (x / stride).floor();
    if (column >= widget.crossAxisCount || x - column * stride > extent) {
      return null;
    }
    final y = local.dy + widget.controller.offset - widget.padding.top;
    if (y < 0) return null;
    final row = (y / stride).floor();
    if (y - row * stride > extent) return null;
    final index = row * widget.crossAxisCount + column;
    return index < widget.itemCount ? index : null;
  }

  void _pointerDown(int index, PointerDownEvent event) {
    if (!widget.enabled || widget.busy) return;
    setState(() {
      pointer = event.pointer;
      startIndex = index;
      startPosition = event.position;
      selectionBase = {
        for (var item = 0; item < widget.itemCount; item++)
          if (widget.isSelected(item)) item,
      };
      dragActive = false;
      dragPosition = null;
    });
  }

  void _applySelection(Offset position) {
    final start = startIndex;
    final target = _indexAt(position);
    if (start == null || target == null) return;
    final next = Set<int>.of(selectionBase);
    final first = start < target ? start : target;
    final last = start > target ? start : target;
    for (var index = first; index <= last; index++) {
      dragValue ? next.add(index) : next.remove(index);
    }
    widget.onSelectionChanged(next);
  }

  void _startAutoScroll() {
    autoScrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final position = dragPosition;
      final box = surfaceKey.currentContext?.findRenderObject() as RenderBox?;
      if (!dragActive ||
          position == null ||
          box == null ||
          !box.hasSize ||
          !widget.controller.hasClients) {
        return;
      }
      final local = box.globalToLocal(position);
      const edge = 72.0;
      double delta = 0;
      if (local.dy < edge) {
        delta = -((edge - local.dy) / edge * 14).clamp(3, 14).toDouble();
      } else if (local.dy > box.size.height - edge) {
        delta = ((local.dy - (box.size.height - edge)) / edge * 14)
            .clamp(3, 14)
            .toDouble();
      }
      if (delta == 0) return;
      final next = (widget.controller.offset + delta)
          .clamp(
            widget.controller.position.minScrollExtent,
            widget.controller.position.maxScrollExtent,
          )
          .toDouble();
      if (next == widget.controller.offset) return;
      widget.controller.jumpTo(next);
      _applySelection(position);
    });
  }

  void _pointerMove(PointerMoveEvent event) {
    final origin = startPosition;
    final start = startIndex;
    if (event.pointer != pointer || origin == null || start == null) return;
    if (!dragActive && (event.position - origin).distance < 6) return;
    if (!dragActive) {
      dragActive = true;
      dragValue = !selectionBase.contains(start);
      _startAutoScroll();
    }
    dragPosition = event.position;
    _applySelection(event.position);
  }

  void _pointerEnd(PointerEvent event) {
    if (event.pointer != pointer) return;
    setState(_resetDrag);
  }

  void _toggleSelection(int index) {
    final next = {
      for (var item = 0; item < widget.itemCount; item++)
        if (widget.isSelected(item)) item,
    };
    if (!next.add(index)) next.remove(index);
    widget.onSelectionChanged(next);
  }

  void _resetDrag() {
    pointer = null;
    startIndex = null;
    startPosition = null;
    dragActive = false;
    dragPosition = null;
    autoScrollTimer?.cancel();
    autoScrollTimer = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    key: surfaceKey,
    child: GridView.builder(
      key: widget.gridKey,
      controller: widget.controller,
      physics: pointer == null ? null : const NeverScrollableScrollPhysics(),
      padding: widget.padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.crossAxisCount,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: widget.itemCount,
      itemBuilder: (context, index) {
        final item = widget.itemBuilder(context, index);
        if (!widget.enabled) return item;
        return Stack(
          fit: StackFit.expand,
          children: [
            item,
            Positioned(
              right: 0,
              top: 0,
              child: Listener(
                key: widget.selectionKeyBuilder(index),
                onPointerDown: (event) => _pointerDown(index, event),
                onPointerMove: _pointerMove,
                onPointerUp: _pointerEnd,
                onPointerCancel: _pointerEnd,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleSelection(index),
                  child: const SizedBox.square(dimension: 44),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class SystemAlbumScreen extends StatefulWidget {
  const SystemAlbumScreen(this.app, this.album, {super.key, this.title});

  final CleanerState app;
  final SystemAlbumSummary album;
  final String? title;

  @override
  State<SystemAlbumScreen> createState() => _SystemAlbumScreenState();
}

class _SystemAlbumScreenState extends State<SystemAlbumScreen> {
  final gridController = ScrollController();
  List<MediaRecord>? records;
  final selected = <String, MediaRecord>{};
  int loaded = 0;
  int total = 0;
  bool selecting = false;
  bool queueing = false;

  String get title =>
      widget.title ??
      (widget.album.path.name.trim().isEmpty
          ? '未命名相册'
          : widget.album.path.name);

  Scope get scope => Scope('album:${widget.album.path.id}', title);

  @override
  void initState() {
    super.initState();
    total = widget.album.count;
    _load();
  }

  Future<void> _load() async {
    final result = await widget.app.media.recordsForAlbum(widget.album.path, (
      value,
      maximum,
    ) {
      if (mounted) {
        setState(() {
          loaded = value;
          total = maximum;
        });
      }
    });
    final queuedIds = (await widget.app.store.queue())
        .map((row) => row['media_id'] as String)
        .toSet();
    final visible = result
        .where((record) => !queuedIds.contains(record.id))
        .toList();
    if (mounted) {
      setState(() {
        records = visible;
        total = visible.length;
        selected.removeWhere(
          (id, _) => !visible.any((record) => record.id == id),
        );
      });
    }
  }

  Future<void> _review([int? initialIndex]) async {
    final items = records;
    if (items == null || items.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          widget.app,
          scope,
          initialIndex: initialIndex,
          source: items,
          includeReviewedSource: initialIndex != null,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _toggleSelecting() => setState(() {
    selecting = !selecting;
    selected.clear();
  });

  void _toggleSelected(MediaRecord item) => setState(() {
    selected.containsKey(item.id)
        ? selected.remove(item.id)
        : selected[item.id] = item;
  });

  void _updateSelectedIndexes(Set<int> indexes) {
    final items = records;
    if (items == null) return;
    setState(() {
      selected
        ..clear()
        ..addEntries(
          indexes.map((index) => MapEntry(items[index].id, items[index])),
        );
    });
  }

  @override
  void dispose() {
    gridController.dispose();
    super.dispose();
  }

  Future<void> _queueSelected() async {
    if (queueing || selected.isEmpty) return;
    setState(() => queueing = true);
    final items = selected.values.toList();
    try {
      for (final item in items) {
        await widget.app.store.act(scope, item, ReviewAction.delete);
      }
      if (!mounted) return;
      setState(() {
        records = records
            ?.where((item) => !selected.containsKey(item.id))
            .toList();
        total = records?.length ?? 0;
        selected.clear();
        selecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已将 ${items.length} 项加入待删除队列，可在队列中复核。')),
      );
    } finally {
      if (mounted) setState(() => queueing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    extendBodyBehindAppBar: true,
    appBar: _UnifiedAppBar(
      title: title,
      subtitle: selecting
          ? '已选择 ${selected.length} 项'
          : '${records?.length ?? total} 个项目',
      actions: [
        if (!selecting)
          _HeaderBrowseButton(
            key: const Key('album-start-review'),
            onPressed: records?.isNotEmpty == true && !queueing
                ? _review
                : null,
          ),
        _HeaderSelectButton(
          selecting: selecting,
          onPressed: records == null || queueing ? null : _toggleSelecting,
        ),
      ],
    ),
    body: Stack(
      children: [
        if (records == null)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 14),
                Text('正在读取 $loaded / $total 项'),
              ],
            ),
          )
        else if (records!.isEmpty)
          const Center(child: Text('这个相册没有可访问的媒体'))
        else
          _DragSelectableGrid(
            gridKey: const Key('album-media-grid'),
            controller: gridController,
            padding: EdgeInsets.fromLTRB(
              4,
              _appHeaderInset(context) + 6,
              4,
              82,
            ),
            crossAxisCount: _photoGridColumnCount(
              MediaQuery.sizeOf(context).width,
            ),
            itemCount: records!.length,
            selectionKeyBuilder: (index) =>
                ValueKey('album-select-${records![index].id}'),
            enabled: selecting,
            busy: queueing,
            isSelected: (index) => selected.containsKey(records![index].id),
            onSelectionChanged: _updateSelectedIndexes,
            itemBuilder: (context, index) {
              final item = records![index];
              final isSelected = selected.containsKey(item.id);
              return ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  key: ValueKey('album-media-${item.id}'),
                  onTap: selecting
                      ? () => _toggleSelected(item)
                      : () => _review(index),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MediaThumb(widget.app.media, item.id),
                      if (item.live)
                        Positioned(
                          key: ValueKey('live-photo-marker-${item.id}'),
                          left: 6,
                          top: 6,
                          child: const _LivePhotoBadge(),
                        ),
                      if (item.type == 2)
                        Positioned(
                          right: 7,
                          bottom: 7,
                          child: _VideoDurationBadge(item.duration),
                        ),
                      if (selecting) ...[
                        Positioned(
                          right: 6,
                          top: 6,
                          child: _SelectionMarker(selected: isSelected),
                        ),
                        if (isSelected)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: _systemBlue,
                                    width: 3,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        if (selecting)
          _BatchQueueBar(
            selectedCount: selected.length,
            busy: queueing,
            onQueue: _queueSelected,
          ),
      ],
    ),
  );
}

class SimilarPhotosScreen extends StatefulWidget {
  const SimilarPhotosScreen(this.app, {super.key});

  final CleanerState app;

  @override
  State<SimilarPhotosScreen> createState() => _SimilarPhotosScreenState();
}

enum _SimilarityAction { checkUpdates, rebuild }

class _SimilarPhotosScreenState extends State<SimilarPhotosScreen> {
  List<SimilarPhotoGroup>? groups;
  int processed = 0;
  int total = 0;
  int? generatedAt;
  int loadToken = 0;
  bool failed = false;
  bool refreshing = false;
  bool cancelRequested = false;
  bool cancelled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final token = ++loadToken;
    setState(() {
      failed = false;
      refreshing = true;
      cancelRequested = false;
      cancelled = false;
      processed = 0;
      total = 0;
    });
    try {
      final status = await widget.app.media.cachedSimilarPhotoStatus(
        widget.app.store,
      );
      final cached = status.hasAnalysis
          ? await widget.app.media.cachedSimilarPhotos(widget.app.store)
          : null;
      if (mounted && token == loadToken && cached != null) {
        setState(() {
          groups = cached;
          generatedAt = status.generatedAt;
        });
      }
      if (!force && status.hasAnalysis && !status.needsUpdate) {
        if (mounted && token == loadToken) {
          setState(() => refreshing = false);
        }
        return;
      }
      final result = await widget.app.media.findSimilarPhotos(
        widget.app.store,
        (value, maximum) {
          if (!mounted || token != loadToken) return;
          setState(() {
            processed = value;
            total = maximum;
          });
        },
        shouldCancel: () => cancelRequested || !mounted || token != loadToken,
      );
      final refreshedAt = await widget.app.media.cachedSimilarityGeneratedAt(
        widget.app.store,
      );
      if (mounted && token == loadToken) {
        setState(() {
          groups = result;
          generatedAt = refreshedAt;
          refreshing = false;
        });
      }
    } on SimilarityScanCancelled {
      if (mounted && token == loadToken) {
        setState(() {
          cancelled = true;
          refreshing = false;
        });
      }
    } catch (_) {
      if (mounted && token == loadToken) {
        setState(() {
          failed = true;
          refreshing = false;
        });
      }
    }
  }

  void _cancel() {
    if (!refreshing || cancelRequested) return;
    setState(() => cancelRequested = true);
  }

  Future<void> _rebuildAnalysis() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新分析全部照片？'),
        content: const Text('这会清除现有分析缓存并重新检查全部照片，照片较多时可能需要较长时间。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重新分析'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.app.store.clearSimilarityAnalysis();
      if (!mounted) return;
      setState(() {
        groups = null;
        generatedAt = null;
      });
      await _load(force: true);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  void _selectAction(_SimilarityAction action) {
    switch (action) {
      case _SimilarityAction.checkUpdates:
        unawaited(_load(force: true));
        break;
      case _SimilarityAction.rebuild:
        unawaited(_rebuildAnalysis());
        break;
    }
  }

  @override
  void dispose() {
    cancelRequested = true;
    loadToken++;
    super.dispose();
  }

  Future<void> _review(SimilarPhotoGroup group, int index) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          widget.app,
          Scope('similar:${group.items.first.id}', '相似照片'),
          initialIndex: index,
          source: group.items,
          includeReviewedSource: true,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _loading() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 14),
        Text(total == 0 ? '正在读取照片' : '正在分析 $processed / $total 张'),
        const SizedBox(height: 8),
        const Text(
          '仅在本机分析缩略图，不会上传照片',
          style: TextStyle(color: _secondaryLabel, fontSize: 12),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: cancelRequested ? null : _cancel,
          child: Text(cancelRequested ? '正在停止…' : '停止分析'),
        ),
      ],
    ),
  );

  Widget _results() {
    final currentGroups = groups!;
    return CustomScrollView(
      key: const Key('similar-groups'),
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: _appHeaderInset(context))),
        if (generatedAt != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                '最近分析 ${_formatSimilarityGeneratedAt(generatedAt!)}',
                style: const TextStyle(color: _secondaryLabel, fontSize: 12),
              ),
            ),
          ),
        if (refreshing) ...[
          const SliverToBoxAdapter(
            child: LinearProgressIndicator(minHeight: 2),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      total == 0
                          ? '正在检查新增或修改的照片'
                          : '正在更新 $processed / $total 张',
                      style: const TextStyle(
                        color: _secondaryLabel,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: cancelRequested ? null : _cancel,
                    child: Text(cancelRequested ? '正在停止…' : '停止'),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (cancelled)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
              child: Row(
                children: [
                  const Expanded(child: Text('分析已停止，当前显示上次结果')),
                  TextButton(
                    onPressed: () => _load(force: true),
                    child: const Text('继续分析'),
                  ),
                ],
              ),
            ),
          ),
        if (failed)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
              child: Row(
                children: [
                  const Expanded(child: Text('更新失败，当前显示上次结果')),
                  TextButton(
                    onPressed: () => _load(force: true),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        if (currentGroups.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('暂未发现相似照片')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, itemIndex) {
                if (itemIndex.isOdd) return const SizedBox(height: 22);
                final groupIndex = itemIndex ~/ 2;
                final group = currentGroups[groupIndex];
                return _SimilarPhotoGroupCard(
                  key: ValueKey('similar-group-${group.items.first.id}'),
                  app: widget.app,
                  group: group,
                  groupIndex: groupIndex,
                  onReview: (index) => _review(group, index),
                );
              }, childCount: currentGroups.length * 2 - 1),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: _UnifiedAppBar(
      title: '相似照片',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Center(
            child: _GlassSurface(
              radius: 22,
              child: PopupMenuButton<_SimilarityAction>(
                key: const Key('similar-actions'),
                tooltip: '分析选项',
                enabled: !refreshing,
                padding: EdgeInsets.zero,
                onSelected: _selectAction,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _SimilarityAction.checkUpdates,
                    child: Text('检查更新'),
                  ),
                  PopupMenuItem(
                    value: _SimilarityAction.rebuild,
                    child: Text('重新分析全部照片'),
                  ),
                ],
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.more_horiz_rounded, size: 22),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    body: groups != null
        ? _results()
        : failed
        ? Padding(
            padding: EdgeInsets.only(top: _appHeaderInset(context)),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('相似照片分析失败'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => _load(force: true),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          )
        : cancelled
        ? Padding(
            padding: EdgeInsets.only(top: _appHeaderInset(context)),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('已停止相似照片分析'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => _load(force: true),
                    child: const Text('继续分析'),
                  ),
                ],
              ),
            ),
          )
        : Padding(
            padding: EdgeInsets.only(top: _appHeaderInset(context)),
            child: _loading(),
          ),
  );
}

class _SimilarPhotoGroupCard extends StatefulWidget {
  const _SimilarPhotoGroupCard({
    super.key,
    required this.app,
    required this.group,
    required this.groupIndex,
    required this.onReview,
  });

  final CleanerState app;
  final SimilarPhotoGroup group;
  final int groupIndex;
  final ValueChanged<int> onReview;

  @override
  State<_SimilarPhotoGroupCard> createState() => _SimilarPhotoGroupCardState();
}

class _SimilarPhotoGroupCardState extends State<_SimilarPhotoGroupCard> {
  final selected = <String>{};
  Map<String, int>? sizes;
  int sizeLoadToken = 0;
  bool queueing = false;

  String get itemSignature => widget.group.items.map((item) => item.id).join();

  MediaRecord get keeper => recommendedSimilarPhotoKeeper(widget.group.items);

  @override
  void initState() {
    super.initState();
    _loadSizes();
  }

  @override
  void didUpdateWidget(covariant _SimilarPhotoGroupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSignature = oldWidget.group.items.map((item) => item.id).join();
    if (oldSignature != itemSignature) {
      selected.clear();
      sizes = null;
      _loadSizes();
    }
  }

  Future<void> _loadSizes() async {
    final token = ++sizeLoadToken;
    final result = await widget.app.media.mediaSizes(
      widget.group.items.map((item) => item.id),
    );
    if (mounted && token == sizeLoadToken) setState(() => sizes = result);
  }

  void _toggle(String id) => setState(() {
    selected.contains(id) ? selected.remove(id) : selected.add(id);
  });

  void _toggleRest() {
    final rest = widget.group.items
        .where((item) => item.id != keeper.id)
        .map((item) => item.id)
        .toSet();
    setState(() {
      if (rest.every(selected.contains)) {
        selected.removeAll(rest);
      } else {
        selected.addAll(rest);
      }
    });
  }

  Future<void> _queueSelected() async {
    if (queueing || selected.isEmpty) return;
    final items = widget.group.items
        .where((item) => selected.contains(item.id))
        .toList();
    setState(() => queueing = true);
    try {
      final scope = Scope('similar:${widget.group.items.first.id}', '相似照片');
      for (final item in items) {
        await widget.app.store.act(scope, item, ReviewAction.delete);
      }
      if (!mounted) return;
      setState(selected.clear);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已加入待删除队列')));
    } finally {
      if (mounted) setState(() => queueing = false);
    }
  }

  String _spaceSummary() {
    if (sizes == null) return '正在估算可释放空间';
    final ids = selected.isEmpty
        ? widget.group.items
              .where((item) => item.id != keeper.id)
              .map((item) => item.id)
        : selected;
    var bytes = 0;
    var unknown = 0;
    for (final id in ids) {
      final size = sizes![id] ?? 0;
      if (size > 0) {
        bytes += size;
      } else {
        unknown++;
      }
    }
    final prefix = selected.isEmpty
        ? '建议可释放 ${_formatResultBytes(bytes)}'
        : '已选择 ${selected.length} 张 · ${_formatResultBytes(bytes)}';
    return unknown == 0 ? prefix : '$prefix · $unknown 张大小待估算';
  }

  @override
  void dispose() {
    sizeLoadToken++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rest = widget.group.items.where((item) => item.id != keeper.id);
    final allRestSelected = rest.every((item) => selected.contains(item.id));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _secondarySystemBackground,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '第 ${widget.groupIndex + 1} 组 · '
                    '${widget.group.items.length} 张',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  key: ValueKey(
                    'similar-select-rest-${widget.group.items.first.id}',
                  ),
                  onPressed: queueing ? null : _toggleRest,
                  child: Text(allRestSelected ? '清空' : '选择其余'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 116,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.group.items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = widget.group.items[index];
                  final isKeeper = item.id == keeper.id;
                  final isSelected = selected.contains(item.id);
                  return SizedBox.square(
                    dimension: 116,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Material(
                            color: _systemBackground,
                            child: InkWell(
                              key: ValueKey('similar-${item.id}'),
                              onTap: queueing
                                  ? null
                                  : () => widget.onReview(index),
                              child: MediaThumb(widget.app.media, item.id),
                            ),
                          ),
                        ),
                        if (isSelected)
                          IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _systemBlue,
                                  width: 3,
                                ),
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        if (isKeeper)
                          Positioned(
                            left: 7,
                            bottom: 7,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xD9000000),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 4,
                                ),
                                child: Text(
                                  '推荐保留',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: SizedBox.square(
                            dimension: 48,
                            child: IconButton(
                              key: ValueKey('similar-select-${item.id}'),
                              onPressed: queueing
                                  ? null
                                  : () => _toggle(item.id),
                              padding: const EdgeInsets.all(10),
                              icon: _SelectionMarker(selected: isSelected),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _spaceSummary(),
              style: const TextStyle(color: _secondaryLabel, fontSize: 13),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: ValueKey('similar-queue-${widget.group.items.first.id}'),
                onPressed: selected.isEmpty || queueing ? null : _queueSelected,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text(queueing ? '正在加入…' : '加入待删除'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoDurationBadge extends StatelessWidget {
  const _VideoDurationBadge(this.seconds);

  final int seconds;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xB3000000),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(
        _formatMediaDuration(seconds),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    ),
  );
}

class ScopeScreen extends StatefulWidget {
  const ScopeScreen(
    this.app,
    this.scope, {
    super.key,
    this.startReview = false,
    this.initialPendingOnly = false,
  });
  final CleanerState app;
  final Scope scope;
  final bool startReview;
  final bool initialPendingOnly;

  @override
  State<ScopeScreen> createState() => _ScopeScreenState();
}

enum _LibraryTimeMode { year, month, all }

class _ScopeScreenState extends State<ScopeScreen> {
  final ScrollController gridController = ScrollController();
  final selected = <String, MediaRecord>{};
  List<MediaRecord>? selectionItems;
  bool pendingOnly = false;
  bool reviewStarted = false;
  bool libraryMenuExpanded = true;
  bool showingAlbums = false;
  bool selecting = false;
  bool selectionLoading = false;
  bool queueing = false;
  _LibraryTimeMode libraryTimeMode = _LibraryTimeMode.all;
  int count = 0;
  int pendingCount = 0;
  int? focusedIndex;

  @override
  void initState() {
    super.initState();
    pendingOnly = widget.initialPendingOnly;
    _refresh();
  }

  @override
  void dispose() {
    gridController.dispose();
    super.dispose();
  }

  Future<void> _refresh({String? focusId}) async {
    if (widget.app.downAction != DownSwipeAction.pending && pendingOnly) {
      pendingOnly = false;
    }
    final total = await widget.app.store.count(
      widget.scope,
      pendingOnly: pendingOnly,
    );
    final pending = widget.app.downAction == DownSwipeAction.pending
        ? await widget.app.store.count(widget.scope, pendingOnly: true)
        : 0;
    final focus = focusId == null
        ? null
        : await widget.app.store.positionOf(
            widget.scope,
            focusId,
            pendingOnly: pendingOnly,
          );
    if (!mounted) return;
    setState(() {
      count = total;
      pendingCount = pending;
      focusedIndex = focus != null && focus >= 0 ? focus : null;
    });
    if (focusedIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !gridController.hasClients) return;
        final columns = _photoGridColumnCount(MediaQuery.sizeOf(context).width);
        const horizontalPadding = 8.0;
        final topPadding = _appHeaderInset(context) + 6;
        const spacing = 4.0;
        final itemExtent =
            (MediaQuery.sizeOf(context).width -
                horizontalPadding -
                spacing * (columns - 1)) /
            columns;
        final row = focusedIndex! ~/ columns;
        final itemCenter =
            topPadding + row * (itemExtent + spacing) + itemExtent / 2;
        final offset =
            (itemCenter - gridController.position.viewportDimension / 2)
                .clamp(
                  gridController.position.minScrollExtent,
                  gridController.position.maxScrollExtent,
                )
                .toDouble();
        gridController.animateTo(
          offset,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      });
    }
    if (widget.startReview && !reviewStarted && total > 0) {
      reviewStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open(null);
      });
    }
  }

  Future<void> _open(int? index) async {
    final source = index == null
        ? null
        : await widget.app.store.list(widget.scope, pendingOnly: pendingOnly);
    if (!mounted) return;
    final focusId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          widget.app,
          widget.scope,
          initialIndex: index,
          pendingOnly: pendingOnly,
          source: source,
          includeReviewedSource: index != null,
        ),
      ),
    );
    await _refresh(focusId: focusId);
  }

  Future<void> _toggleSelecting() async {
    if (selecting) {
      setState(_leaveSelection);
      return;
    }
    if (selectionLoading) return;
    setState(() => selectionLoading = true);
    final items = await widget.app.store.list(
      widget.scope,
      pendingOnly: pendingOnly,
    );
    if (!mounted) return;
    setState(() {
      selectionItems = items;
      selecting = true;
      selectionLoading = false;
      selected.clear();
    });
  }

  void _toggleSelected(MediaRecord item) => setState(() {
    selected.containsKey(item.id)
        ? selected.remove(item.id)
        : selected[item.id] = item;
  });

  void _leaveSelection() {
    selecting = false;
    selectionItems = null;
    selected.clear();
  }

  void _updateSelectedIndexes(Set<int> indexes) {
    final items = selectionItems;
    if (items == null) return;
    setState(() {
      selected
        ..clear()
        ..addEntries(
          indexes.map((index) => MapEntry(items[index].id, items[index])),
        );
    });
  }

  Future<void> _queueSelected() async {
    if (queueing || selected.isEmpty) return;
    setState(() => queueing = true);
    final items = selected.values.toList();
    try {
      for (final item in items) {
        await widget.app.store.act(widget.scope, item, ReviewAction.delete);
      }
      if (!mounted) return;
      setState(_leaveSelection);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已将 ${items.length} 项加入待删除队列，可在队列中复核。')),
      );
    } finally {
      if (mounted) setState(() => queueing = false);
    }
  }

  bool _handleScroll(ScrollNotification notification) {
    if (notification.depth == 0 &&
        notification is ScrollStartNotification &&
        libraryMenuExpanded &&
        !showingAlbums &&
        mounted) {
      setState(() => libraryMenuExpanded = false);
    }
    return false;
  }

  List<(Scope, String, int)> _periods() {
    if (libraryTimeMode == _LibraryTimeMode.month) {
      return [
        for (final row in widget.app.months)
          (
            Scope.month(row.$1),
            row.$1 == 'unknown'
                ? '时间未知'
                : '${row.$1.substring(0, 4)}年'
                      '${int.parse(row.$1.substring(5, 7))}月',
            row.$2,
          ),
      ];
    }
    final totals = <String, int>{};
    for (final row in widget.app.months) {
      final year = row.$1 == 'unknown' ? 'unknown' : row.$1.substring(0, 4);
      totals[year] = (totals[year] ?? 0) + row.$2;
    }
    return [
      for (final entry in totals.entries)
        (
          entry.key == 'unknown'
              ? Scope.month('unknown')
              : Scope.year(entry.key),
          entry.key == 'unknown' ? '时间未知' : '${entry.key}年',
          entry.value,
        ),
    ];
  }

  Widget _periodGrid() {
    final periods = _periods();
    if (periods.isEmpty) return const Center(child: Text('还没有可浏览的媒体'));
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScroll,
      child: GridView.builder(
        key: ValueKey('library-${libraryTimeMode.name}-grid'),
        padding: EdgeInsets.fromLTRB(20, _appHeaderInset(context) + 4, 20, 116),
        itemCount: periods.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 14,
          childAspectRatio: 0.94,
        ),
        itemBuilder: (context, index) {
          final period = periods[index];
          return _LibraryPeriodCard(
            widget.app,
            period.$1,
            label: period.$2,
            count: period.$3,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScopeScreen(widget.app, period.$1),
                ),
              );
              await _refresh();
            },
          );
        },
      ),
    );
  }

  Widget _scopeMediaTile(MediaRecord item, int index) {
    final isSelected = selected.containsKey(item.id);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        key: ValueKey('scope-media-${item.id}'),
        onTap: selecting ? () => _toggleSelected(item) : () => _open(index),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MediaThumb(widget.app.media, item.id),
            if (item.live)
              Positioned(
                key: ValueKey('live-photo-marker-${item.id}'),
                left: 6,
                top: 6,
                child: const _LivePhotoBadge(),
              ),
            if (item.type == 2)
              Positioned(
                right: 7,
                bottom: 7,
                child: _VideoDurationBadge(item.duration),
              ),
            if (selecting) ...[
              Positioned(
                right: 6,
                top: 6,
                child: _SelectionMarker(selected: isSelected),
              ),
              if (isSelected)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _systemBlue, width: 3),
                      ),
                    ),
                  ),
                ),
            ],
            if (focusedIndex == index)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    key: Key('focused-scope-item-$index'),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFFE9A23B),
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mediaGrid() {
    if (count == 0) {
      return const Center(child: Text('这里还没有可浏览的媒体'));
    }
    final items = selectionItems;
    final itemCount = selecting && items != null ? items.length : count;
    final showsPendingFilter =
        !selecting &&
        !showingAlbums &&
        libraryTimeMode == _LibraryTimeMode.all &&
        widget.app.downAction == DownSwipeAction.pending;
    final padding = EdgeInsets.fromLTRB(
      4,
      _appHeaderInset(context) + (showsPendingFilter ? 50 : 6),
      4,
      widget.scope.key == Scope.all.key && !pendingOnly ? 116 : 82,
    );
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScroll,
      child: _DragSelectableGrid(
        gridKey: const Key('scope-media-grid'),
        controller: gridController,
        padding: padding,
        crossAxisCount: _photoGridColumnCount(MediaQuery.sizeOf(context).width),
        itemCount: itemCount,
        selectionKeyBuilder: (index) =>
            ValueKey('scope-select-${items?[index].id ?? index}'),
        enabled: selecting && items != null,
        busy: queueing,
        isSelected: (index) =>
            items != null && selected.containsKey(items[index].id),
        onSelectionChanged: _updateSelectedIndexes,
        itemBuilder: (context, index) {
          if (selecting && items != null) {
            return _scopeMediaTile(items[index], index);
          }
          return FutureBuilder<MediaRecord?>(
            future: widget.app.store.at(
              widget.scope,
              index,
              pendingOnly: pendingOnly,
            ),
            builder: (context, snapshot) {
              final item = snapshot.data;
              return item == null
                  ? const ColoredBox(color: Color(0xFFE7ECEB))
                  : _scopeMediaTile(item, index);
            },
          );
        },
      ),
    );
  }

  Widget _content() {
    if (showingAlbums) {
      return _LibraryAlbumsView(
        widget.app,
        topPadding: _appHeaderInset(context),
      );
    }
    if (libraryTimeMode != _LibraryTimeMode.all) return _periodGrid();
    return _mediaGrid();
  }

  Widget _libraryControls() => SafeArea(
    minimum: const EdgeInsets.fromLTRB(16, 0, 16, 4),
    child: Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.0).animate(animation),
            child: child,
          ),
        ),
        child: libraryMenuExpanded || showingAlbums
            ? Align(
                key: const Key('library-view-toggle'),
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: 220,
                  child: _LibraryGlassControl(
                    child: Row(
                      children: [
                        Expanded(
                          child: _LibraryControlItem(
                            icon: Icons.photo_library_outlined,
                            label: '图库',
                            selected: !showingAlbums,
                            onTap: () => setState(() => showingAlbums = false),
                          ),
                        ),
                        Expanded(
                          child: _LibraryControlItem(
                            icon: Icons.photo_album_outlined,
                            label: '相册',
                            selected: showingAlbums,
                            onTap: () => setState(() => showingAlbums = true),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : Row(
                key: const Key('library-time-controls'),
                children: [
                  SizedBox.square(
                    dimension: 56,
                    child: _LibraryGlassControl(
                      child: IconButton(
                        key: const Key('library-circle-button'),
                        tooltip: '展开图库与相册',
                        onPressed: () =>
                            setState(() => libraryMenuExpanded = true),
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          color: _systemBlue,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 218,
                    child: _LibraryGlassControl(
                      child: Row(
                        children: [
                          for (final mode in _LibraryTimeMode.values)
                            Expanded(
                              child: _LibraryControlItem(
                                key: ValueKey('library-mode-${mode.name}'),
                                label: switch (mode) {
                                  _LibraryTimeMode.year => '年',
                                  _LibraryTimeMode.month => '月',
                                  _LibraryTimeMode.all => '全部',
                                },
                                selected: libraryTimeMode == mode,
                                selectedColor: Colors.white,
                                onTap: () =>
                                    setState(() => libraryTimeMode = mode),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    extendBodyBehindAppBar: true,
    appBar: _UnifiedAppBar(
      title: showingAlbums ? '相册' : widget.scope.label,
      subtitle: showingAlbums
          ? '按相册浏览'
          : selecting
          ? '已选择 ${selected.length} 项'
          : '$count 个项目',
      actions: [
        if (!showingAlbums && libraryTimeMode == _LibraryTimeMode.all)
          if (!selecting)
            _HeaderBrowseButton(
              key: const Key('media-browse-button'),
              onPressed: count == 0 || queueing ? null : () => _open(null),
            ),
        if (!showingAlbums && libraryTimeMode == _LibraryTimeMode.all)
          _HeaderSelectButton(
            selecting: selecting,
            onPressed: count == 0 || queueing || selectionLoading
                ? null
                : _toggleSelecting,
          ),
      ],
    ),
    body: Stack(
      children: [
        Positioned.fill(child: _content()),
        if (!selecting &&
            !showingAlbums &&
            libraryTimeMode == _LibraryTimeMode.all &&
            widget.app.downAction == DownSwipeAction.pending)
          Positioned(
            top: _appHeaderInset(context) + 4,
            right: 12,
            child: _GlassSurface(
              radius: 16,
              child: TextButton.icon(
                key: const Key('pending-filter-entry'),
                onPressed: () {
                  setState(() {
                    pendingOnly = !pendingOnly;
                    _leaveSelection();
                  });
                  _refresh();
                },
                style: TextButton.styleFrom(
                  foregroundColor: _appleGlassForeground,
                ),
                icon: Icon(
                  pendingOnly
                      ? Icons.photo_library_outlined
                      : Icons.schedule_outlined,
                  size: 18,
                ),
                label: Text(pendingOnly ? '返回全部' : '待定 $pendingCount'),
              ),
            ),
          ),
        if (widget.scope.key == Scope.all.key && !pendingOnly && !selecting)
          _libraryControls(),
        if (selecting)
          _BatchQueueBar(
            selectedCount: selected.length,
            busy: queueing,
            onQueue: _queueSelected,
          ),
      ],
    ),
  );
}

class _LibraryGlassControl extends StatelessWidget {
  const _LibraryGlassControl({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => _GlassSurface(
    color: _appleGlass,
    radius: 16,
    child: SizedBox(height: 52, child: child),
  );
}

class _LibraryControlItem extends StatelessWidget {
  const _LibraryControlItem({
    super.key,
    this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedColor = Colors.white,
  });

  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color selectedColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(4),
    child: Material(
      color: selected ? selectedColor : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 21,
                color: selected ? _systemBlue : _secondaryLabel,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? _primaryLabel : _secondaryLabel,
                fontSize: 15,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LibraryPeriodCard extends StatelessWidget {
  const _LibraryPeriodCard(
    this.app,
    this.scope, {
    required this.label,
    required this.count,
    required this.onTap,
  });

  final CleanerState app;
  final Scope scope;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FutureBuilder<MediaRecord?>(
    future: app.store.at(scope, 0),
    builder: (context, snapshot) => InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (snapshot.data case final media?)
              MediaThumb(app.media, media.id)
            else
              const ColoredBox(color: Color(0xFFE7ECEB)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC000000)],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 15,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count 项',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LibraryAlbumsView extends StatefulWidget {
  const _LibraryAlbumsView(this.app, {this.topPadding = 0});

  final CleanerState app;
  final double topPadding;

  @override
  State<_LibraryAlbumsView> createState() => _LibraryAlbumsViewState();
}

class _LibraryAlbumsViewState extends State<_LibraryAlbumsView> {
  late Future<List<SystemAlbumSummary>> albums;

  @override
  void initState() {
    super.initState();
    albums = _loadVisibleSystemAlbums(widget.app);
  }

  Future<void> _openAlbum(SystemAlbumSummary album) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SystemAlbumScreen(widget.app, album)),
    );
    if (mounted) setState(() => albums = _loadVisibleSystemAlbums(widget.app));
  }

  Widget _section(String title, List<SystemAlbumSummary> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 18, 0, 12),
          child: Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
        GridView.builder(
          key: ValueKey('library-album-grid-$title'),
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _albumGridColumnCount(
              MediaQuery.sizeOf(context).width,
            ),
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
            childAspectRatio: 0.78,
          ),
          itemBuilder: (context, index) {
            final album = items[index];
            return InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => _openAlbum(album),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      key: ValueKey('library-album-cover-${album.path.id}'),
                      borderRadius: BorderRadius.circular(12),
                      child: album.coverId == null
                          ? const ColoredBox(
                              color: Color(0xFFEAF0FF),
                              child: Center(
                                child: Icon(Icons.photo_library_outlined),
                              ),
                            )
                          : MediaThumb(widget.app.media, album.coverId!),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    album.path.name.trim().isEmpty ? '未命名相册' : album.path.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${album.count} 项',
                    style: const TextStyle(
                      color: _secondaryLabel,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SystemAlbumSummary>>(
    future: albums,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      final items = snapshot.data ?? const <SystemAlbumSummary>[];
      if (items.isEmpty) return const Center(child: Text('还没有可浏览的相册'));
      return ListView(
        key: const Key('library-albums-view'),
        padding: EdgeInsets.fromLTRB(20, widget.topPadding + 4, 20, 116),
        children: [
          _section(
            '手机相册',
            items
                .where((album) => album.group == SystemAlbumGroup.album)
                .toList(),
          ),
          _section(
            '人物',
            items
                .where((album) => album.group == SystemAlbumGroup.people)
                .toList(),
          ),
          _section(
            '系统分类',
            items
                .where((album) => album.group == SystemAlbumGroup.smart)
                .toList(),
          ),
        ],
      );
    },
  );
}

class MediaThumb extends StatefulWidget {
  const MediaThumb(
    this.media,
    this.id, {
    super.key,
    this.width = 320,
    this.height = 320,
    this.fit = BoxFit.cover,
    this.initialBytes,
    this.placeholderColor = const Color(0xFFE7ECEB),
    this.showPlaceholderIcon = true,
  });
  final MediaRepository media;
  final String id;
  final int width;
  final int height;
  final BoxFit fit;
  final Uint8List? initialBytes;
  final Color placeholderColor;
  final bool showPlaceholderIcon;

  @override
  State<MediaThumb> createState() => _MediaThumbState();
}

class _MediaThumbState extends State<MediaThumb> {
  late Future<Uint8List?> bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MediaThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) _load();
  }

  void _load() =>
      bytes = widget.media.thumbnail(widget.id, widget.width, widget.height);

  @override
  Widget build(BuildContext context) {
    if (widget.initialBytes != null) {
      return Image.memory(
        widget.initialBytes!,
        fit: widget.fit,
        gaplessPlayback: true,
      );
    }
    return FutureBuilder<Uint8List?>(
      future: bytes,
      builder: (context, snapshot) => snapshot.data == null
          ? ColoredBox(
              color: widget.placeholderColor,
              child: widget.showPlaceholderIcon
                  ? const Center(child: Icon(Icons.image_outlined))
                  : null,
            )
          : Image.memory(
              snapshot.data!,
              fit: widget.fit,
              gaplessPlayback: true,
            ),
    );
  }
}

class ReviewScreen extends StatefulWidget {
  const ReviewScreen(
    this.app,
    this.scope, {
    super.key,
    this.initialIndex,
    this.pendingOnly = false,
    this.source,
    this.includeReviewedSource = false,
  });
  final CleanerState app;
  final Scope scope;
  final int? initialIndex;
  final bool pendingOnly;
  final List<MediaRecord>? source;
  final bool includeReviewedSource;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen>
    with SingleTickerProviderStateMixin {
  static const reviewBackground = _systemBackground;
  static const _horizontalFlingVelocity = 700.0;
  static const _verticalFlingVelocity = 900.0;
  static const _horizontalFlingDistance = 24.0;
  static const _verticalFlingDistance = 32.0;
  static const _verticalActionDistance = 76.0;
  static const _filmstripItemWidth = 36.0;
  static const _filmstripSelectedWidth = 42.0;

  int index = 0;
  int total = 0;
  MediaRecord? current;
  Uint8List? currentPreview;
  MediaRecord? incoming;
  Uint8List? incomingPreview;
  MediaRecord? previousItem;
  Uint8List? previousPreview;
  MediaRecord? nextItem;
  Uint8List? nextPreview;
  final Map<String, Future<Uint8List?>> previewCache = {};
  final Map<int, Future<MediaRecord?>> filmstripItemCache = {};
  final ScrollController filmstripController = ScrollController();
  bool filmstripUserScrolling = false;
  bool filmstripSelecting = false;
  int filmstripSelectionRequest = 0;
  int queueCount = 0;
  final List<ActionSnapshot> undoHistory = [];
  bool currentFavorite = false;
  bool busy = false;
  Offset dragOffset = Offset.zero;
  Offset panOffset = Offset.zero;
  Axis? dragAxis;
  double actionScale = 1;
  int browseDirection = 1;
  double zoom = 1;
  final ValueNotifier<int> gestureFrame = ValueNotifier(0);
  List<MediaRecord>? sourceItems;
  late final List<MediaRecord>? sourceOrder;
  late final AnimationController motion;
  late Animation<Offset> motionAnimation;
  late Animation<double> scaleAnimation;
  bool exitPromptOpen = false;
  bool exitPromptBypassed = false;
  bool exitRequestedWhileBusy = false;
  OverlayEntry? edgeNotice;
  String? edgeNoticeMessage;
  Timer? edgeNoticeTimer;

  @override
  void initState() {
    super.initState();
    sourceOrder = widget.source == null
        ? null
        : List<MediaRecord>.of(widget.source!);
    motion =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 170),
        )..addListener(() {
          if (mounted) {
            dragOffset = motionAnimation.value;
            actionScale = scaleAnimation.value;
            gestureFrame.value++;
          }
        });
    motionAnimation = const AlwaysStoppedAnimation(Offset.zero);
    scaleAnimation = const AlwaysStoppedAnimation(1);
    _initialize();
  }

  @override
  void dispose() {
    edgeNotice?.remove();
    edgeNotice = null;
    edgeNoticeTimer?.cancel();
    motion.dispose();
    filmstripController.dispose();
    gestureFrame.dispose();
    super.dispose();
  }

  void _showEdgeNotice(String message) {
    if (edgeNotice != null && edgeNoticeMessage == message) return;
    edgeNotice?.remove();
    edgeNoticeTimer?.cancel();
    late final OverlayEntry notice;
    notice = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: DecoratedBox(
                  key: const Key('edge-notice'),
                  decoration: BoxDecoration(
                    color: const Color(0xE6FFFFFF),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 12,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 13,
                    ),
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: _primaryLabel,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    edgeNotice = notice;
    edgeNoticeMessage = message;
    Overlay.of(context).insert(notice);
    edgeNoticeTimer = Timer(const Duration(milliseconds: 1200), () {
      if (edgeNotice != notice) return;
      notice.remove();
      edgeNotice = null;
      edgeNoticeMessage = null;
      edgeNoticeTimer = null;
    });
  }

  Future<void> _initialize() async {
    if (sourceOrder != null) await _refreshSource();
    total =
        sourceItems?.length ??
        await widget.app.store.count(
          widget.scope,
          pendingOnly: widget.pendingOnly,
          unreviewedOnly: !widget.pendingOnly,
        );
    queueCount = (await widget.app.store.queue()).length;
    if (widget.initialIndex != null) {
      if (sourceOrder != null) {
        index = _sourcePositionAt(widget.initialIndex!);
      } else if (widget.pendingOnly) {
        index = widget.initialIndex!;
      } else {
        final selected = await widget.app.store.at(
          widget.scope,
          widget.initialIndex!,
        );
        index = selected == null
            ? 0
            : await widget.app.store.positionOf(
                widget.scope,
                selected.id,
                unreviewedOnly: true,
              );
      }
    } else if (!widget.pendingOnly) {
      final anchor = await widget.app.store.anchor(widget.scope);
      if (anchor != null) {
        index = sourceOrder == null
            ? await widget.app.store.positionOf(
                widget.scope,
                anchor,
                unreviewedOnly: true,
              )
            : _sourcePositionOf(anchor);
        if (index < 0) index = 0;
      }
    }
    if (index >= total && total > 0) index = total - 1;
    await _load();
  }

  Future<void> _refreshSource() async {
    final original = sourceOrder;
    if (original == null) return;
    if (widget.pendingOnly || widget.includeReviewedSource) {
      sourceItems = List<MediaRecord>.of(original);
      return;
    }
    final reviewed = await widget.app.store.reviewedIds(widget.scope);
    sourceItems = original
        .where((item) => !reviewed.contains(item.id))
        .toList();
  }

  int _sourcePositionAt(int originalIndex) {
    final original = sourceOrder!;
    if (original.isEmpty) return 0;
    final capped = originalIndex.clamp(0, original.length - 1);
    return _sourcePositionOf(original[capped].id);
  }

  int _sourcePositionOf(String id) {
    final active = sourceItems!;
    final exact = active.indexWhere((item) => item.id == id);
    if (exact >= 0) return exact;
    final originalIndex = sourceOrder!.indexWhere((item) => item.id == id);
    if (originalIndex < 0) return 0;
    final activeIds = active.map((item) => item.id).toSet();
    return sourceOrder!
        .take(originalIndex)
        .where((item) => activeIds.contains(item.id))
        .length;
  }

  Future<void> _load() async {
    final (item, preview) = await _loadAt(index);
    final favorite = item != null && await widget.app.store.isFavorite(item.id);
    if (!mounted) return;
    setState(() {
      current = item;
      currentPreview = preview;
      currentFavorite = favorite;
      incoming = null;
      incomingPreview = null;
      previousItem = null;
      previousPreview = null;
      nextItem = null;
      nextPreview = null;
      zoom = 1;
      actionScale = 1;
      dragAxis = null;
      panOffset = Offset.zero;
    });
    if (item != null) await widget.app.store.saveAnchor(widget.scope, item);
    _prefetchAround(index);
    _centerFilmstrip();
  }

  Future<MediaRecord?> _itemAt(int target) async {
    if (target < 0 || target >= total) return null;
    return sourceItems == null
        ? widget.app.store.at(
            widget.scope,
            target,
            pendingOnly: widget.pendingOnly,
            unreviewedOnly: !widget.pendingOnly,
          )
        : sourceItems![target];
  }

  Future<MediaRecord?> _filmstripItemAt(int target) =>
      filmstripItemCache.putIfAbsent(target, () => _itemAt(target));

  void _centerFilmstrip() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !filmstripController.hasClients) return;
      final position = filmstripController.position;
      final target = (index * _filmstripItemWidth).clamp(
        0.0,
        position.maxScrollExtent,
      );
      filmstripController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  int _filmstripIndexAt(double offset) => total == 0
      ? 0
      : (offset / _filmstripItemWidth).round().clamp(0, total - 1);

  bool _handleFilmstripScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      filmstripUserScrolling = notification.dragDetails != null;
    }
    if (filmstripUserScrolling && notification is ScrollUpdateNotification) {
      unawaited(
        _selectFromFilmstrip(_filmstripIndexAt(notification.metrics.pixels)),
      );
    }
    if (filmstripUserScrolling && notification is ScrollEndNotification) {
      filmstripUserScrolling = false;
      final target = _filmstripIndexAt(notification.metrics.pixels);
      filmstripController.animateTo(
        target * _filmstripItemWidth,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    }
    return false;
  }

  Future<void> _selectFromFilmstrip(int target) async {
    if (target < 0 || target >= total || (busy && !filmstripSelecting)) return;
    final request = ++filmstripSelectionRequest;
    if (target == index) {
      if (filmstripSelecting) {
        filmstripSelecting = false;
        _finishBusy();
      }
      return;
    }
    if (!filmstripSelecting) {
      setState(() {
        filmstripSelecting = true;
        busy = true;
      });
    }
    try {
      final (loadedItem, loadedPreview) = await _loadAt(target);
      if (loadedItem == null) return;
      final loadedFavorite = await widget.app.store.isFavorite(loadedItem.id);
      if (!mounted || request != filmstripSelectionRequest) return;
      browseDirection = target > index ? 1 : -1;
      setState(() {
        index = target;
        current = loadedItem;
        currentPreview = loadedPreview;
        currentFavorite = loadedFavorite;
        incoming = null;
        incomingPreview = null;
        previousItem = null;
        previousPreview = null;
        nextItem = null;
        nextPreview = null;
        dragOffset = Offset.zero;
        zoom = 1;
        actionScale = 1;
        dragAxis = null;
        panOffset = Offset.zero;
      });
      await widget.app.store.saveAnchor(widget.scope, loadedItem);
      _prefetchAround(target);
    } finally {
      if (mounted && request == filmstripSelectionRequest) {
        filmstripSelecting = false;
        _finishBusy();
      }
    }
  }

  void _finishBusy() {
    if (!mounted) return;
    setState(() => busy = false);
    if (exitRequestedWhileBusy) {
      exitRequestedWhileBusy = false;
      unawaited(_requestExit());
    }
  }

  Future<Uint8List?> _previewFor(MediaRecord item) {
    final cached = previewCache[item.id];
    if (cached != null) return cached;
    final future = widget.app.media.thumbnail(item.id, 1080, 1080);
    previewCache[item.id] = future;
    if (previewCache.length > 6) {
      final protected = {current?.id, incoming?.id, item.id};
      for (final id in previewCache.keys.toList()) {
        if (previewCache.length <= 6) break;
        if (!protected.contains(id)) previewCache.remove(id);
      }
    }
    return future;
  }

  Future<(MediaRecord?, Uint8List?)> _loadAt(int target) async {
    final item = await _itemAt(target);
    return (item, item == null ? null : await _previewFor(item));
  }

  Future<void> _prefetchAround(int target) async {
    final expectedId = current?.id;
    final neighbors = await Future.wait([
      _loadAt(target - 1),
      _loadAt(target + 1),
    ]);
    if (!mounted || index != target || current?.id != expectedId) return;
    previousItem = neighbors[0].$1;
    previousPreview = neighbors[0].$2;
    nextItem = neighbors[1].$1;
    nextPreview = neighbors[1].$2;
    if (dragOffset.dx.abs() > dragOffset.dy.abs()) {
      browseDirection = dragOffset.dx < 0 ? 1 : -1;
      incoming = browseDirection > 0 ? nextItem : previousItem;
      incomingPreview = browseDirection > 0 ? nextPreview : previousPreview;
    }
    gestureFrame.value++;
  }

  Future<void> _animateTo(
    Offset target, {
    double targetScale = 1,
    double velocity = 0,
    Duration? duration,
  }) async {
    final distance = (target - dragOffset).distance;
    motion.duration =
        duration ??
        (velocity <= 0
            ? const Duration(milliseconds: 220)
            : Duration(
                milliseconds: (distance / velocity * 1000).round().clamp(
                  140,
                  240,
                ),
              ));
    motionAnimation = Tween<Offset>(
      begin: dragOffset,
      end: target,
    ).animate(CurvedAnimation(parent: motion, curve: Curves.easeOutCubic));
    scaleAnimation = Tween<double>(
      begin: actionScale,
      end: targetScale,
    ).animate(CurvedAnimation(parent: motion, curve: Curves.easeInCubic));
    motion.reset();
    await motion.forward();
  }

  Future<void> _returnToCenter({double velocity = 0}) async {
    await _animateTo(Offset.zero, velocity: velocity);
    if (mounted) {
      setState(() {
        incoming = null;
        incomingPreview = null;
        dragAxis = null;
        panOffset = Offset.zero;
        actionScale = 1;
      });
    }
  }

  Future<void> _move(int amount, {double velocity = 0}) async {
    if (busy || current == null) return;
    final next = index + amount;
    if (next < 0 || next >= total) {
      await _returnToCenter(velocity: velocity);
      if (!mounted) return;
      _showEdgeNotice(next < 0 ? '已经是第一张' : '已经是最后一张');
      return;
    }
    setState(() => busy = true);
    try {
      browseDirection = amount;
      final cachedItem = amount == 1
          ? nextItem
          : amount == -1
          ? previousItem
          : null;
      final cachedPreview = amount == 1
          ? nextPreview
          : amount == -1
          ? previousPreview
          : null;
      final loadedItem = cachedItem ?? await _itemAt(next);
      if (loadedItem == null) return;
      if (!mounted) return;
      setState(() {
        incoming = loadedItem;
        incomingPreview = cachedPreview;
      });
      final width = MediaQuery.sizeOf(context).width;
      final animation = _animateTo(
        Offset(amount > 0 ? -width : width, 0),
        velocity: velocity,
      );
      final preview = cachedPreview == null
          ? _previewFor(loadedItem)
          : Future<Uint8List?>.value(cachedPreview);
      final favorite = widget.app.store.isFavorite(loadedItem.id);
      final loadedPreview = await preview;
      final loadedFavorite = await favorite;
      await animation;
      index = next;
      if (mounted) {
        setState(() {
          current = loadedItem;
          currentPreview = loadedPreview;
          currentFavorite = loadedFavorite;
          incoming = null;
          incomingPreview = null;
          previousItem = null;
          previousPreview = null;
          nextItem = null;
          nextPreview = null;
          dragOffset = Offset.zero;
          zoom = 1;
          actionScale = 1;
          dragAxis = null;
          panOffset = Offset.zero;
        });
      }
      await widget.app.store.saveAnchor(widget.scope, loadedItem);
      _prefetchAround(index);
      _centerFilmstrip();
    } finally {
      _finishBusy();
    }
  }

  Future<void> _act(ReviewAction action, {double velocity = 0}) async {
    if (busy || current == null) return;
    final previous = index;
    final actedItem = current!;
    final predictedItem =
        (browseDirection < 0 ? previousItem : nextItem) ?? actedItem;
    final predictedPreview =
        (browseDirection < 0 ? previousPreview : nextPreview) ?? currentPreview;
    setState(() {
      busy = true;
      incoming = predictedItem;
      incomingPreview = predictedPreview;
    });
    HapticFeedback.mediumImpact();
    final size = MediaQuery.sizeOf(context);
    final animation = action == ReviewAction.delete
        ? _animateTo(
            Offset(size.width * 0.4, -size.height * 0.44),
            targetScale: 0.1,
            velocity: velocity,
            duration: const Duration(milliseconds: 170),
          )
        : _animateTo(Offset(0, size.height * 1.08), velocity: velocity);
    try {
      final snapshot = await widget.app.store.act(
        widget.scope,
        actedItem,
        action,
      );
      if (snapshot != null) undoHistory.add(snapshot);
      queueCount = (await widget.app.store.queue()).length;
      final removedFromView =
          action != ReviewAction.skip &&
          (!widget.pendingOnly || action != ReviewAction.pending);
      if (removedFromView && sourceItems != null) {
        sourceItems!.removeWhere((item) => item.id == actedItem.id);
      }
      filmstripItemCache.clear();
      total =
          sourceItems?.length ??
          await widget.app.store.count(
            widget.scope,
            pendingOnly: widget.pendingOnly,
            unreviewedOnly: !widget.pendingOnly,
          );
      final next = removedFromView
          ? previous + (browseDirection < 0 ? -1 : 0)
          : previous + browseDirection;
      if (total == 0 || next < 0) {
        index = 0;
      } else if (next >= total) {
        index = total - 1;
      } else {
        index = next;
      }
      final (loadedItem, loadedPreview) = await _loadAt(index);
      final loadedFavorite =
          loadedItem != null &&
          await widget.app.store.isFavorite(loadedItem.id);
      if (!mounted) return;
      setState(() {
        incoming = loadedItem;
        incomingPreview = loadedPreview;
      });
      await animation;
      if (mounted) {
        setState(() {
          current = loadedItem;
          currentPreview = loadedPreview;
          currentFavorite = loadedFavorite;
          incoming = null;
          incomingPreview = null;
          previousItem = null;
          previousPreview = null;
          nextItem = null;
          nextPreview = null;
          dragOffset = Offset.zero;
          zoom = 1;
          actionScale = 1;
          dragAxis = null;
          panOffset = Offset.zero;
        });
      }
      if (loadedItem != null) {
        await widget.app.store.saveAnchor(widget.scope, loadedItem);
      }
      _prefetchAround(index);
      _centerFilmstrip();
    } finally {
      _finishBusy();
    }
  }

  void _onPanUpdate(Offset delta) {
    if (busy || current == null) return;
    panOffset += delta;
    if (dragAxis == null && panOffset.distance < 8) return;
    if (dragAxis == null) {
      final horizontal = panOffset.dx.abs();
      final vertical = panOffset.dy.abs();
      final larger = horizontal >= vertical ? horizontal : vertical;
      final smaller = horizontal >= vertical ? vertical : horizontal;
      if (larger < smaller * 1.25 && panOffset.distance < 24) return;
      dragAxis = panOffset.dx.abs() >= panOffset.dy.abs()
          ? Axis.horizontal
          : Axis.vertical;
    }
    final next = dragAxis == Axis.horizontal
        ? Offset(panOffset.dx, 0)
        : Offset(0, panOffset.dy);
    dragOffset = next;
    if (dragAxis == Axis.vertical) {
      incoming = null;
      incomingPreview = null;
    } else {
      browseDirection = next.dx < 0 ? 1 : -1;
      incoming = browseDirection > 0 ? nextItem : previousItem;
      incomingPreview = browseDirection > 0 ? nextPreview : previousPreview;
    }
    gestureFrame.value++;
  }

  bool _commitsSwipe({
    required double distance,
    required double velocity,
    required double crossVelocity,
    required double distanceThreshold,
    required double flingDistance,
    required double flingVelocity,
  }) =>
      distance.abs() >= distanceThreshold ||
      (distance.abs() >= flingDistance &&
          velocity.abs() >= flingVelocity &&
          velocity.abs() >= crossVelocity.abs() * 1.2 &&
          (velocity == 0 || distance.sign == velocity.sign));

  Future<void> _onPanEnd(Velocity velocity) async {
    if (busy || current == null) return;
    final speed = velocity.pixelsPerSecond;
    final verticalCommit = _commitsSwipe(
      distance: dragOffset.dy,
      velocity: speed.dy,
      crossVelocity: speed.dx,
      distanceThreshold: _verticalActionDistance,
      flingDistance: _verticalFlingDistance,
      flingVelocity: _verticalFlingVelocity,
    );
    if (dragAxis == Axis.vertical && verticalCommit) {
      if (dragOffset.dy > 0 &&
          (widget.pendingOnly ||
              widget.app.downAction == DownSwipeAction.returnToAlbum)) {
        setState(() => busy = true);
        await _animateTo(
          Offset(0, MediaQuery.sizeOf(context).height * 1.08),
          velocity: speed.dy.abs(),
        );
        if (!mounted) return;
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          await _exitReview();
        } else {
          _finishBusy();
          await _returnToCenter(velocity: speed.dy.abs());
        }
        return;
      }
      final action = dragOffset.dy < 0
          ? ReviewAction.delete
          : widget.app.downAction.reviewAction;
      if (action == null) {
        await _returnToCenter(velocity: speed.dy.abs());
      } else {
        await _act(action, velocity: speed.dy.abs());
      }
      return;
    }
    final horizontalDistance = (MediaQuery.sizeOf(context).width * 0.16).clamp(
      52.0,
      68.0,
    );
    final horizontalCommit = _commitsSwipe(
      distance: dragOffset.dx,
      velocity: speed.dx,
      crossVelocity: speed.dy,
      distanceThreshold: horizontalDistance,
      flingDistance: _horizontalFlingDistance,
      flingVelocity: _horizontalFlingVelocity,
    );
    if (dragAxis == Axis.horizontal && horizontalCommit) {
      await _move(dragOffset.dx < 0 ? 1 : -1, velocity: speed.dx.abs());
      return;
    }
    await _returnToCenter(velocity: speed.distance);
  }

  Future<void> _undo() async {
    if (busy || undoHistory.isEmpty) return;
    setState(() => busy = true);
    try {
      final snapshot = undoHistory.last;
      await widget.app.store.undo(snapshot);
      undoHistory.removeLast();
      queueCount = (await widget.app.store.queue()).length;
      if (sourceOrder != null) await _refreshSource();
      filmstripItemCache.clear();
      total =
          sourceItems?.length ??
          await widget.app.store.count(
            widget.scope,
            pendingOnly: widget.pendingOnly,
            unreviewedOnly: !widget.pendingOnly,
          );
      index = sourceItems == null
          ? await widget.app.store.positionOf(
              widget.scope,
              snapshot.mediaId,
              pendingOnly: widget.pendingOnly,
              unreviewedOnly: !widget.pendingOnly,
            )
          : _sourcePositionOf(snapshot.mediaId);
      if (index < 0) index = 0;
      await _load();
    } finally {
      _finishBusy();
    }
  }

  Future<void> _toggleFavorite() async {
    if (busy || current == null) return;
    final id = current!.id;
    final next = !currentFavorite;
    await widget.app.store.setFavorite(id, next);
    if (!mounted || current?.id != id) return;
    HapticFeedback.selectionClick();
    setState(() => currentFavorite = next);
  }

  Future<void> _requestExit() async {
    if (exitPromptOpen) return;
    if (busy) {
      exitRequestedWhileBusy = true;
      return;
    }
    exitPromptOpen = true;
    try {
      final latestQueueCount = (await widget.app.store.queue()).length;
      if (!mounted) return;
      if (latestQueueCount != queueCount) {
        setState(() => queueCount = latestQueueCount);
      }
      if (current != null || latestQueueCount == 0 || exitPromptBypassed) {
        await _exitReview();
        return;
      }
      final openQueue = await showAdaptiveDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog.adaptive(
          title: const Text('别忘了删除照片'),
          content: Text(
            '本次整理已完成，待删除队列中还有 $latestQueueCount 项照片或视频尚未最终删除。是否现在进入队列复核并删除？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('稍后再说'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('进入待删除队列删除'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (openQueue == true) {
        setState(() => exitPromptBypassed = true);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => QueueScreen(widget.app)),
        );
      } else {
        await _exitReview();
      }
    } finally {
      exitPromptOpen = false;
    }
  }

  Future<void> _exitReview() async {
    if (!mounted) return;
    setState(() => exitPromptBypassed = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Navigator.pop(context, current?.id);
  }

  Widget _mediaStage(MediaRecord item) => _AppleZoomableMedia(
    key: ValueKey('review-media-${item.id}'),
    surfaceKey: const Key('review-gesture'),
    viewerKey: const Key('review-zoom'),
    onSwipeUpdate: _onPanUpdate,
    onSwipeEnd: _onPanEnd,
    onSwipeCancel: () => unawaited(_returnToCenter()),
    onZoomChanged: (isZoomed) {
      zoom = isZoomed ? 2 : 1;
      gestureFrame.value++;
    },
    child: ValueListenableBuilder<int>(
      valueListenable: gestureFrame,
      builder: (context, _, _) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final horizontalTransition =
            dragOffset.dx.abs() > dragOffset.dy.abs() && dragOffset.dx != 0;
        final incomingOffset = horizontalTransition
            ? Offset(
                dragOffset.dx +
                    (browseDirection > 0 ? screenWidth : -screenWidth),
                0,
              )
            : Offset.zero;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (incoming != null)
              Transform.translate(
                key: const Key('incoming-media-translation'),
                offset: incomingOffset,
                child: MediaView(
                  widget.app.media,
                  incoming!,
                  key: ValueKey('incoming-${incoming!.id}'),
                  autoplay: false,
                  previewBytes: incomingPreview,
                  controlsVisible: false,
                ),
              ),
            Transform.translate(
              key: const Key('media-drag-translation'),
              offset: dragOffset,
              child: Transform.scale(
                key: const Key('action-media-scale'),
                scale: actionScale,
                child: MediaView(
                  widget.app.media,
                  item,
                  key: ValueKey(item.id),
                  previewBytes: currentPreview,
                  controlsVisible: zoom <= 1.001,
                  videoProgressBottom: 142,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _filmstrip() => SizedBox(
    key: const Key('review-filmstrip'),
    height: 46,
    child: LayoutBuilder(
      builder: (context, constraints) =>
          NotificationListener<ScrollNotification>(
            onNotification: _handleFilmstripScroll,
            child: ListView.builder(
              controller: filmstripController,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.symmetric(
                horizontal:
                    (constraints.maxWidth - _filmstripSelectedWidth) / 2,
              ),
              itemCount: total,
              itemBuilder: (context, target) => FutureBuilder<MediaRecord?>(
                future: _filmstripItemAt(target),
                builder: (context, snapshot) {
                  final media = snapshot.data;
                  final selected = target == index;
                  return GestureDetector(
                    key: media == null
                        ? ValueKey('review-filmstrip-$target')
                        : ValueKey('review-filmstrip-${media.id}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: media == null || selected || busy
                        ? null
                        : () {
                            filmstripController.animateTo(
                              target * _filmstripItemWidth,
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                            );
                            unawaited(_selectFromFilmstrip(target));
                          },
                    child: Center(
                      child: AnimatedContainer(
                        key: media == null
                            ? ValueKey('review-filmstrip-tile-$target')
                            : ValueKey('review-filmstrip-tile-${media.id}'),
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOutCubic,
                        width: selected
                            ? _filmstripSelectedWidth
                            : _filmstripItemWidth,
                        height: selected ? 46 : 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A3342),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected
                                ? Colors.white
                                : const Color(0x8899A7BC),
                            width: selected ? 2.5 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: media == null
                            ? const Icon(
                                Icons.image_outlined,
                                color: Colors.white70,
                              )
                            : Stack(
                                fit: StackFit.expand,
                                children: [
                                  MediaThumb(
                                    widget.app.media,
                                    media.id,
                                    width: 96,
                                    height: 96,
                                  ),
                                  if (media.type == 2)
                                    const Center(
                                      child: Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 18,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black,
                                            blurRadius: 6,
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final item = current;
    final content = AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: reviewBackground,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: reviewBackground,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (item == null)
              Center(
                child: _glass(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  child: const Text(
                    '本范围已整理完成',
                    style: TextStyle(
                      color: _appleGlassForeground,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else
              _mediaStage(item),
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: _immersiveHeaderHeight,
              child: _SystemTopGradient(key: Key('page-top-gradient')),
            ),
            ValueListenableBuilder<int>(
              valueListenable: gestureFrame,
              builder: (context, _, _) => Visibility(
                visible: zoom <= 1.001,
                child: SafeArea(
                  minimum: _immersiveHeaderPadding,
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: _glassIcon(
                          tooltip: '返回',
                          icon: Icons.arrow_back_ios_new_rounded,
                          onPressed: busy ? null : _requestExit,
                          diameter: 44,
                          iconSize: 19,
                          color: _appleGlass,
                        ),
                      ),
                      Align(
                        alignment: Alignment.topCenter,
                        child: _glass(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 8,
                          ),
                          color: _appleGlass,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item == null
                                    ? '$total / $total'
                                    : '${index + 1} / $total',
                                style: const TextStyle(
                                  color: _appleGlassForeground,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              if (item != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _formatMediaDate(item.takenAt),
                                  style: const TextStyle(
                                    color: _secondaryLabel,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.topRight,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ValueListenableBuilder<int>(
                              valueListenable: gestureFrame,
                              builder: (context, _, _) {
                                final progress =
                                    dragOffset.dy < 0 &&
                                        dragOffset.dy.abs() >
                                            dragOffset.dx.abs()
                                    ? (dragOffset.dy.abs() /
                                              _verticalActionDistance)
                                          .clamp(0.0, 1.0)
                                    : 0.0;
                                return Transform.scale(
                                  key: const Key('delete-control-scale'),
                                  scale: 1 + progress * 0.2,
                                  child: _glassIcon(
                                    tooltip: '待删除队列',
                                    icon: Icons.delete_outline_rounded,
                                    onPressed: busy
                                        ? null
                                        : () async {
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    QueueScreen(widget.app),
                                              ),
                                            );
                                            final latestCount =
                                                (await widget.app.store.queue())
                                                    .length;
                                            if (mounted) {
                                              setState(
                                                () => queueCount = latestCount,
                                              );
                                            }
                                          },
                                    diameter: 44,
                                    iconSize: 20,
                                    color: Color.lerp(
                                      _appleGlass,
                                      const Color(0xF2FF3B30),
                                      progress,
                                    )!,
                                  ),
                                );
                              },
                            ),
                            if (queueCount > 0)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  key: const Key('queue-count-badge'),
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _systemRed,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '$queueCount',
                                    maxLines: 1,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 58,
                        child: _filmstrip(),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.pendingOnly)
                              _glassIcon(
                                key: const Key('pending-restore-control'),
                                tooltip: '恢复',
                                icon: Icons.undo_rounded,
                                onPressed: busy || item == null
                                    ? null
                                    : () => _act(ReviewAction.restore),
                              )
                            else
                              _glassIcon(
                                key: const Key('favorite-control'),
                                tooltip: currentFavorite ? '取消收藏' : '收藏',
                                icon: currentFavorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                onPressed: busy || item == null
                                    ? null
                                    : _toggleFavorite,
                                color: currentFavorite
                                    ? const Color(0xD9E9A23B)
                                    : _appleGlass,
                              ),
                            const SizedBox(width: 12),
                            _glassIcon(
                              key: const Key('undo-control'),
                              tooltip: '撤销上一步',
                              icon: Icons.undo_rounded,
                              onPressed: busy || undoHistory.isEmpty
                                  ? null
                                  : _undo,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return PopScope<Object?>(
      canPop: exitPromptBypassed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestExit());
      },
      child: content,
    );
  }

  Widget _glass({
    required Widget child,
    required EdgeInsets padding,
    Color color = _appleGlass,
  }) => _GlassSurface(color: color, radius: 22, padding: padding, child: child);

  Widget _glassIcon({
    Key? key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    double diameter = 48,
    double iconSize = 22,
    Color color = _appleGlass,
  }) => _GlassIconButton(
    buttonKey: key,
    tooltip: tooltip,
    icon: icon,
    onPressed: onPressed,
    diameter: diameter,
    iconSize: iconSize,
    color: color,
  );
}

class MediaView extends StatefulWidget {
  const MediaView(
    this.media,
    this.item, {
    super.key,
    this.previewBytes,
    this.autoplay = true,
    this.videoProgressBottom = 10,
    this.controlsVisible = true,
    this.volumeButtonEvents,
  });
  final MediaRepository media;
  final MediaRecord item;
  final Uint8List? previewBytes;
  final bool autoplay;
  final double videoProgressBottom;
  final bool controlsVisible;
  final Stream<void>? volumeButtonEvents;

  @override
  State<MediaView> createState() => _MediaViewState();
}

class _MediaViewState extends State<MediaView> {
  VideoPlayerController? player;
  bool loading = false;
  bool muted = true;
  bool livePhotoPressed = false;
  bool livePhotoPlaying = false;
  bool videoCompleted = false;
  StreamSubscription<void>? volumeButtonSubscription;

  bool get canPlayLivePhoto =>
      widget.item.live && widget.media.supportsLivePhotoPlayback;

  @override
  void initState() {
    super.initState();
    _listenForHardwareVolume();
    if (widget.item.type == 2 && widget.autoplay) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    }
  }

  @override
  void dispose() {
    unawaited(volumeButtonSubscription?.cancel());
    player?.removeListener(_handlePlayback);
    player?.dispose();
    super.dispose();
  }

  void _listenForHardwareVolume() {
    if (widget.item.type != 2 || !widget.autoplay) return;
    final events = widget.volumeButtonEvents;
    if (events == null && !Platform.isAndroid && !Platform.isIOS) return;
    volumeButtonSubscription = (events ?? _hardwareVolumeButtonEvents).listen(
      (_) => unawaited(_enableSoundFromHardwareVolume()),
    );
  }

  Future<void> _enableSoundFromHardwareVolume() async {
    if (!muted) return;
    muted = false;
    if (mounted) setState(() {});
    final controller = player;
    if (controller?.value.isInitialized == true) await controller!.setVolume(1);
  }

  void _handlePlayback() {
    final controller = player;
    if (controller == null || widget.item.type != 2 || videoCompleted) return;
    final value = controller.value;
    if (!value.isInitialized || value.duration <= Duration.zero) return;
    if (value.position < value.duration) return;
    videoCompleted = true;
    unawaited(controller.pause());
    unawaited(controller.seekTo(Duration.zero));
    if (mounted) setState(() {});
  }

  Future<void> _play() async {
    if (loading) return;
    if (player != null) {
      if (videoCompleted) {
        videoCompleted = false;
        await player!.seekTo(Duration.zero);
        await player!.play();
      } else {
        player!.value.isPlaying ? await player!.pause() : await player!.play();
      }
      setState(() {});
      return;
    }
    setState(() => loading = true);
    try {
      final file = await widget.media.videoFile(widget.item.id);
      if (file == null) throw StateError('视频不可访问');
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setVolume(0);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      player = controller;
      controller.addListener(_handlePlayback);
      videoCompleted = false;
      await controller.play();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('视频暂时无法播放，可继续整理')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _startLivePhoto() async {
    if (!canPlayLivePhoto || loading) return;
    livePhotoPressed = true;
    final existing = player;
    if (existing != null) {
      await existing.seekTo(Duration.zero);
      if (!livePhotoPressed) return;
      await existing.play();
      if (mounted) setState(() => livePhotoPlaying = true);
      return;
    }
    setState(() => loading = true);
    try {
      final file = await widget.media.livePhotoVideoFile(widget.item.id);
      if (file == null || !livePhotoPressed) return;
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted || !livePhotoPressed) {
        await controller.dispose();
        return;
      }
      player = controller;
      await controller.play();
      if (mounted) setState(() => livePhotoPlaying = true);
    } catch (_) {
      // Keep the still image visible when the paired motion resource is unavailable.
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _stopLivePhoto() async {
    if (!canPlayLivePhoto) return;
    livePhotoPressed = false;
    final controller = player;
    if (controller != null) {
      await controller.pause();
      await controller.seekTo(Duration.zero);
    }
    if (mounted) setState(() => livePhotoPlaying = false);
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _toggleMuted() async {
    final controller = player;
    if (controller?.value.isInitialized != true) return;
    final nextMuted = !muted;
    await controller!.setVolume(nextMuted ? 0 : 1);
    if (mounted) setState(() => muted = nextMuted);
  }

  Widget _soundButton({required bool enabled}) => IconButton(
    key: const Key('video-sound-toggle'),
    tooltip: muted ? '开启声音' : '关闭声音',
    onPressed: enabled ? _toggleMuted : null,
    color: Colors.white,
    disabledColor: Colors.white54,
    icon: Icon(
      muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
      size: 22,
    ),
  );

  Widget _videoProgress() {
    final controller = player;
    if (controller?.value.isInitialized != true) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('0:00'),
              Text(_formatDuration(Duration(seconds: widget.item.duration))),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              const Expanded(
                child: LinearProgressIndicator(
                  value: 0,
                  minHeight: 4,
                  color: Colors.white,
                  backgroundColor: Colors.white38,
                ),
              ),
              const SizedBox(width: 6),
              _soundButton(enabled: false),
            ],
          ),
        ],
      );
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller!,
      builder: (context, value, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(value.position)),
              Text(_formatDuration(value.duration)),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  padding: const EdgeInsets.only(top: 5, bottom: 8),
                  colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white54,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _soundButton(enabled: true),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showVideo =
        player?.value.isInitialized == true &&
        !videoCompleted &&
        (widget.item.type == 2 || livePhotoPlaying);
    final media = showVideo
        ? AspectRatio(
            aspectRatio: player!.value.aspectRatio,
            child: VideoPlayer(player!),
          )
        : MediaThumb(
            widget.media,
            widget.item.id,
            width: 1080,
            height: 1080,
            fit: BoxFit.contain,
            initialBytes: widget.previewBytes,
            placeholderColor: const Color(0xFF62666D),
            showPlaceholderIcon: false,
          );

    return GestureDetector(
      key: canPlayLivePhoto ? const Key('live-photo-hold-target') : null,
      behavior: HitTestBehavior.opaque,
      onLongPressStart: canPlayLivePhoto ? (_) => _startLivePhoto() : null,
      onLongPressEnd: canPlayLivePhoto ? (_) => _stopLivePhoto() : null,
      onLongPressCancel: canPlayLivePhoto ? _stopLivePhoto : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: DecoratedBox(
                key: const Key('media-surface-shadow'),
                decoration: const BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x3D000000),
                      blurRadius: 24,
                      spreadRadius: 1,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      media,
                      if (widget.item.live && widget.controlsVisible)
                        const Positioned(
                          key: Key('live-photo-badge'),
                          left: 12,
                          top: 12,
                          child: _LivePhotoBadge(showLabel: true),
                        ),
                      if (widget.item.type == 2 && widget.controlsVisible)
                        Positioned.fill(
                          child: Center(
                            child: IconButton.filledTonal(
                              tooltip: player?.value.isPlaying == true
                                  ? '暂停视频'
                                  : '播放视频',
                              onPressed: loading ? null : _play,
                              icon: loading
                                  ? const CircularProgressIndicator()
                                  : Icon(
                                      player?.value.isPlaying == true
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.item.type == 2 && widget.controlsVisible)
            Positioned(
              key: const Key('video-progress'),
              left: 30,
              right: 30,
              bottom: widget.videoProgressBottom,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xA6000000),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0x88FFFFFF)),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 12),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    child: _videoProgress(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class QueueScreen extends StatefulWidget {
  const QueueScreen(this.app, {super.key});
  final CleanerState app;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  List<Map<String, Object?>> rows = [];
  final selected = <String>{};
  final queueGridKey = GlobalKey();
  final queueScroll = ScrollController();
  bool busy = false;
  int? selectionPointer;
  int? selectionStartIndex;
  Offset? selectionStartPosition;
  Set<String> selectionBase = {};
  bool selectionDragActive = false;
  bool selectionDragValue = true;
  String? suppressCheckboxId;
  Timer? selectionAutoScrollTimer;
  Offset? selectionDragPosition;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    selectionAutoScrollTimer?.cancel();
    queueScroll.dispose();
    super.dispose();
  }

  void _selectionPointerDown(int index, PointerDownEvent event) {
    if (busy) return;
    setState(() {
      selectionPointer = event.pointer;
      selectionStartIndex = index;
      selectionStartPosition = event.position;
      selectionBase = Set.of(selected);
      selectionDragActive = false;
      selectionDragPosition = null;
      suppressCheckboxId = null;
    });
  }

  int? _queueIndexAt(Offset globalPosition) {
    final box = queueGridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(globalPosition);
    if (local.dx < 8 || local.dx > box.size.width - 8 || local.dy < 0) {
      return null;
    }
    final columns = _photoGridColumnCount(box.size.width);
    const spacing = 4.0;
    final extent = (box.size.width - 16 - spacing * (columns - 1)) / columns;
    final stride = extent + spacing;
    final columnPosition = local.dx - 8;
    final column = (columnPosition / stride).floor();
    if (column < 0 || column >= columns) return null;
    final contentY =
        local.dy +
        (queueScroll.hasClients ? queueScroll.offset : 0) -
        (_appHeaderInset(context) + 52);
    if (contentY < 0) return null;
    final row = (contentY / stride).floor();
    final index = row * columns + column;
    return index >= 0 && index < rows.length ? index : null;
  }

  void _applySelectionAt(Offset position) {
    final start = selectionStartIndex;
    if (start == null) return;
    final target = _queueIndexAt(position);
    if (target == null) return;
    final next = Set<String>.of(selectionBase);
    final first = start < target ? start : target;
    final last = start > target ? start : target;
    for (var index = first; index <= last; index++) {
      final id = rows[index]['media_id'] as String;
      selectionDragValue ? next.add(id) : next.remove(id);
    }
    if (next.length == selected.length && next.containsAll(selected)) return;
    setState(() {
      selected
        ..clear()
        ..addAll(next);
    });
  }

  void _startSelectionAutoScroll() {
    selectionAutoScrollTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) {
        final position = selectionDragPosition;
        final box =
            queueGridKey.currentContext?.findRenderObject() as RenderBox?;
        if (!selectionDragActive ||
            position == null ||
            box == null ||
            !box.hasSize ||
            !queueScroll.hasClients) {
          return;
        }
        final local = box.globalToLocal(position);
        const edge = 72.0;
        double delta = 0;
        if (local.dy < edge) {
          delta = -((edge - local.dy) / edge * 14).clamp(3, 14).toDouble();
        } else if (local.dy > box.size.height - edge) {
          delta = ((local.dy - (box.size.height - edge)) / edge * 14)
              .clamp(3, 14)
              .toDouble();
        }
        if (delta == 0) return;
        final next = (queueScroll.offset + delta)
            .clamp(
              queueScroll.position.minScrollExtent,
              queueScroll.position.maxScrollExtent,
            )
            .toDouble();
        if (next == queueScroll.offset) return;
        queueScroll.jumpTo(next);
        _applySelectionAt(position);
      },
    );
  }

  void _selectionPointerMove(PointerMoveEvent event) {
    final start = selectionStartIndex;
    final origin = selectionStartPosition;
    if (event.pointer != selectionPointer || start == null || origin == null) {
      return;
    }
    if (!selectionDragActive && (event.position - origin).distance < 6) return;
    if (!selectionDragActive) {
      selectionDragActive = true;
      final startId = rows[start]['media_id'] as String;
      selectionDragValue = !selectionBase.contains(startId);
      suppressCheckboxId = startId;
      _startSelectionAutoScroll();
    }
    selectionDragPosition = event.position;
    _applySelectionAt(event.position);
  }

  void _selectionPointerEnd(PointerEvent event) {
    if (event.pointer != selectionPointer) return;
    setState(() {
      selectionPointer = null;
      selectionStartIndex = null;
      selectionStartPosition = null;
      selectionDragActive = false;
      selectionDragPosition = null;
    });
    selectionAutoScrollTimer?.cancel();
    selectionAutoScrollTimer = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      suppressCheckboxId = null;
    });
  }

  Future<void> _load() async {
    final latest = await widget.app.store.queue();
    if (mounted) {
      setState(() {
        rows = latest;
        selected.removeWhere((id) => !rows.any((row) => row['media_id'] == id));
      });
    }
  }

  Future<bool> _restore(Iterable<String> ids) async {
    if (busy) return false;
    final restored = ids.toSet();
    if (restored.isEmpty) return false;
    setState(() => busy = true);
    try {
      for (final id in restored) {
        await widget.app.store.removeFromQueue(id);
      }
      selected.removeAll(restored);
      await _load();
      return true;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _openPreview(String id) async {
    final asset = await widget.app.media.get(id);
    if (asset == null || !mounted) return;
    final media = _mediaRecordFromAsset(id, asset);
    final itemIds = rows.map((row) => row['media_id'] as String).toList();
    final initialIndex = itemIds.indexOf(id);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QueuePreviewScreen(
          widget.app.media,
          media,
          onKeep: () => _restore([id]),
          onDelete: () => _process([id]),
          itemIds: itemIds,
          initialIndex: initialIndex < 0 ? 0 : initialIndex,
          onKeepItem: (target) => _restore([target]),
          onDeleteItem: (target) => _process([target]),
        ),
      ),
    );
  }

  Future<bool> _process(Iterable<String> targets) async {
    if (busy) return false;
    final ids = targets.toSet().toList();
    if (ids.isEmpty) return false;
    final usesTrash = await widget.app.media.usesRecoverableTrash();
    if (!mounted) return false;
    final accepted = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text('删除 ${ids.length} 项？'),
        content: Text(
          Platform.isIOS
              ? '将再次弹出系统确认。iCloud 照片开启时，删除也可能同步到同一 Apple 账户的其他设备。移入最近删除不等于立即释放空间。'
              : usesTrash
              ? '将再次弹出系统确认。媒体将移入设备回收站，具体保留时间由系统决定；移入回收站不等于立即释放空间。'
              : 'Android 10 不提供批量删除授权或统一的媒体回收站，系统会逐项请求删除。确认后将永久删除所选媒体，此操作无法在本应用中恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回复核'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _systemRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续删除'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return false;
    setState(() => busy = true);
    try {
      final sizes = await widget.app.media.mediaSizes(ids);
      final result = await widget.app.media.deleteReviewedMedia(
        widget.app.store,
        ids,
      );
      await widget.app.refresh();
      await _load();
      if (!mounted) return false;
      final counts = <String, int>{};
      for (final status in result.values) {
        counts[status] = (counts[status] ?? 0) + 1;
      }
      final removedIds = result.entries
          .where((entry) => entry.value == 'confirmedRemoved')
          .map((entry) => entry.key)
          .toList();
      final removedBytes = removedIds.fold<int>(
        0,
        (sum, id) => sum + (sizes[id] ?? 0),
      );
      final unknownSizes = removedIds
          .where((id) => (sizes[id] ?? 0) <= 0)
          .length;
      await showAdaptiveDialog<void>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: const Text('清理完成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '本次清理 ${removedIds.length} 项',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '预计涉及空间 ${_formatResultBytes(removedBytes)}',
                style: const TextStyle(
                  color: _systemBlue,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (unknownSizes > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('$unknownSizes 项未能取得文件大小'),
                ),
              const SizedBox(height: 14),
              Text(
                usesTrash
                    ? '媒体已移入系统最近删除/回收站，实际空间将在系统彻底清理后释放。'
                    : '媒体已从设备删除，系统存储统计可能需要片刻刷新。',
                style: const TextStyle(color: _secondaryLabel),
              ),
              if ((counts['cancelled'] ?? 0) > 0 ||
                  (counts['missing'] ?? 0) > 0 ||
                  (counts['unknown'] ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    '未处理：取消 ${counts['cancelled'] ?? 0} · '
                    '不可访问 ${counts['missing'] ?? 0} · '
                    '待核对 ${counts['unknown'] ?? 0}',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('系统处理未完成，请检查权限并在队列中核对状态。')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: _UnifiedAppBar(
      title: '待删除队列',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Center(
            child: _GlassSurface(
              radius: 18,
              child: TextButton(
                onPressed: rows.isEmpty || busy
                    ? null
                    : () => setState(() {
                        if (selected.length == rows.length) {
                          selected.clear();
                        } else {
                          selected.addAll(
                            rows.map((row) => row['media_id'] as String),
                          );
                        }
                      }),
                style: TextButton.styleFrom(
                  foregroundColor: _appleGlassForeground,
                ),
                child: Text(
                  rows.isNotEmpty && selected.length == rows.length
                      ? '取消全选'
                      : '全选',
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: rows.isEmpty
              ? Padding(
                  padding: EdgeInsets.only(top: _appHeaderInset(context)),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 66,
                          color: _tertiaryLabel,
                        ),
                        SizedBox(height: 16),
                        Text(
                          '还没有待删除的照片',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '上滑只会先加入队列，不会直接删除。',
                          style: TextStyle(color: _secondaryLabel),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    GridView.builder(
                      key: queueGridKey,
                      controller: queueScroll,
                      physics: selectionPointer == null
                          ? null
                          : const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        8,
                        _appHeaderInset(context) + 52,
                        8,
                        0,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _photoGridColumnCount(
                          MediaQuery.sizeOf(context).width,
                        ),
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final id = row['media_id'] as String;
                        return ClipRRect(
                          key: ValueKey('queue-item-$id'),
                          borderRadius: BorderRadius.circular(4),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              GestureDetector(
                                onTap: () => _openPreview(id),
                                child: MediaThumb(
                                  widget.app.media,
                                  id,
                                  width: 360,
                                  height: 360,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 2,
                                child: Listener(
                                  key: ValueKey('queue-select-$id'),
                                  onPointerDown: (event) =>
                                      _selectionPointerDown(index, event),
                                  onPointerMove: _selectionPointerMove,
                                  onPointerUp: _selectionPointerEnd,
                                  onPointerCancel: _selectionPointerEnd,
                                  child: SizedBox.square(
                                    dimension: 44,
                                    child: Transform.scale(
                                      scale: 0.95,
                                      child: Checkbox(
                                        value: selected.contains(id),
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        fillColor:
                                            WidgetStateProperty.resolveWith(
                                              (states) =>
                                                  states.contains(
                                                    WidgetState.selected,
                                                  )
                                                  ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                  : Colors.black45,
                                            ),
                                        side: const BorderSide(
                                          color: Colors.white,
                                        ),
                                        onChanged: (value) {
                                          if (suppressCheckboxId == id) return;
                                          setState(() {
                                            if (value == true) {
                                              selected.add(id);
                                            } else {
                                              selected.remove(id);
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (row['status'] == 'unknown' ||
                                  row['status'] == 'missing')
                                Positioned(
                                  left: 5,
                                  top: 5,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      child: Text(
                                        row['status'] == 'missing'
                                            ? '不可访问'
                                            : '待核对',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      top: _appHeaderInset(context) + 4,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _GlassSurface(
                          color: _appleGlass,
                          radius: 15,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text(
                            '${rows.length} 项待复核 · 请确认后再交给系统处理',
                            style: const TextStyle(color: _secondaryLabel),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: _GlassActionButton(
                  buttonKey: const Key('queue-restore-selected'),
                  icon: Icons.undo_rounded,
                  label: '保留 ${selected.length} 项',
                  onPressed: busy || selected.isEmpty
                      ? null
                      : () => _restore(selected.toList()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: _GlassActionButton(
                  buttonKey: const Key('queue-delete-selected'),
                  icon: Icons.delete_outline_rounded,
                  label: busy ? '等待系统处理…' : '删除 ${selected.length} 项',
                  foregroundColor: _systemRed,
                  onPressed: busy || selected.isEmpty
                      ? null
                      : () => _process(selected),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class QueuePreviewScreen extends StatefulWidget {
  const QueuePreviewScreen(
    this.media,
    this.item, {
    super.key,
    required this.onKeep,
    required this.onDelete,
    this.itemIds,
    this.initialIndex = 0,
    this.onKeepItem,
    this.onDeleteItem,
  });

  final MediaRepository media;
  final MediaRecord item;
  final Future<bool> Function() onKeep;
  final Future<bool> Function() onDelete;
  final List<String>? itemIds;
  final int initialIndex;
  final Future<bool> Function(String id)? onKeepItem;
  final Future<bool> Function(String id)? onDeleteItem;

  @override
  State<QueuePreviewScreen> createState() => _QueuePreviewScreenState();
}

class _QueuePreviewScreenState extends State<QueuePreviewScreen>
    with SingleTickerProviderStateMixin {
  late final List<String> ids;
  late int index;
  late final AnimationController motion;
  late Animation<Offset> motionAnimation;
  final records = <String, Future<MediaRecord?>>{};
  Offset dragOffset = Offset.zero;
  Offset panOffset = Offset.zero;
  Axis? dragAxis;
  int browseDirection = 1;
  bool zoomed = false;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    ids = List<String>.of(widget.itemIds ?? [widget.item.id]);
    if (ids.isEmpty) ids.add(widget.item.id);
    index = widget.initialIndex.clamp(0, ids.length - 1);
    records[widget.item.id] = Future.value(widget.item);
    motion =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          if (mounted) setState(() => dragOffset = motionAnimation.value);
        });
    motionAnimation = const AlwaysStoppedAnimation(Offset.zero);
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  Future<MediaRecord?> _record(String id) => records.putIfAbsent(id, () async {
    final asset = await widget.media.get(id);
    return asset == null ? null : _mediaRecordFromAsset(id, asset);
  });

  void _onSwipeUpdate(Offset delta) {
    if (busy || zoomed) return;
    panOffset += delta;
    if (dragAxis == null && panOffset.distance < 8) return;
    if (dragAxis == null) {
      final horizontal = panOffset.dx.abs();
      final vertical = panOffset.dy.abs();
      final larger = horizontal >= vertical ? horizontal : vertical;
      final smaller = horizontal >= vertical ? vertical : horizontal;
      if (larger < smaller * 1.25 && panOffset.distance < 24) return;
      dragAxis = horizontal >= vertical ? Axis.horizontal : Axis.vertical;
    }
    setState(() {
      dragOffset = dragAxis == Axis.horizontal
          ? Offset(panOffset.dx, 0)
          : Offset(0, panOffset.dy);
      if (dragAxis == Axis.horizontal) {
        browseDirection = dragOffset.dx < 0 ? 1 : -1;
      }
    });
  }

  Future<void> _animateTo(Offset target, {double velocity = 0}) async {
    final distance = (target - dragOffset).distance;
    motion.duration = velocity <= 0
        ? const Duration(milliseconds: 220)
        : Duration(
            milliseconds: (distance / velocity * 1000).round().clamp(140, 240),
          );
    motionAnimation = Tween<Offset>(
      begin: dragOffset,
      end: target,
    ).animate(CurvedAnimation(parent: motion, curve: Curves.easeOutCubic));
    await motion.forward(from: 0);
  }

  Future<void> _returnToCenter({double velocity = 0}) async {
    if (dragOffset != Offset.zero) {
      await _animateTo(Offset.zero, velocity: velocity);
    }
    if (!mounted) return;
    setState(() {
      dragOffset = Offset.zero;
      panOffset = Offset.zero;
      dragAxis = null;
    });
  }

  Future<void> _move(int amount, {double velocity = 0}) async {
    final next = index + amount;
    if (next < 0 || next >= ids.length) {
      await _returnToCenter(velocity: velocity);
      return;
    }
    browseDirection = amount;
    unawaited(_record(ids[next]));
    final width = MediaQuery.sizeOf(context).width;
    await _animateTo(
      Offset(amount > 0 ? -width : width, 0),
      velocity: velocity,
    );
    if (!mounted) return;
    setState(() {
      index = next;
      dragOffset = Offset.zero;
      panOffset = Offset.zero;
      dragAxis = null;
      zoomed = false;
    });
  }

  Future<void> _onSwipeEnd(Velocity velocity) async {
    if (busy || zoomed) return;
    final speed = velocity.pixelsPerSecond;
    if (dragAxis == Axis.vertical) {
      final shouldClose =
          dragOffset.dy >= 80 ||
          (dragOffset.dy >= 24 &&
              speed.dy >= 900 &&
              speed.dy.abs() >= speed.dx.abs() * 1.2);
      if (shouldClose) {
        Navigator.maybePop(context);
      } else {
        await _returnToCenter(velocity: speed.distance);
      }
      return;
    }
    final threshold = (MediaQuery.sizeOf(context).width * 0.16).clamp(
      52.0,
      68.0,
    );
    final shouldMove =
        dragOffset.dx.abs() >= threshold ||
        (dragOffset.dx.abs() >= 24 &&
            speed.dx.abs() >= 700 &&
            speed.dx.abs() >= speed.dy.abs() * 1.2);
    if (dragAxis == Axis.horizontal && shouldMove) {
      await _move(dragOffset.dx < 0 ? 1 : -1, velocity: speed.dx.abs());
    } else {
      await _returnToCenter(velocity: speed.distance);
    }
  }

  Future<void> _act({required bool keep}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final id = ids[index];
      final changed = await (keep
          ? widget.onKeepItem?.call(id) ?? widget.onKeep()
          : widget.onDeleteItem?.call(id) ?? widget.onDelete());
      if (!changed || !mounted) return;
      if (ids.length == 1) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        ids.removeAt(index);
        if (index >= ids.length) index = ids.length - 1;
        dragOffset = Offset.zero;
        panOffset = Offset.zero;
        dragAxis = null;
        zoomed = false;
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _media(String id, {bool autoplay = true}) =>
      FutureBuilder<MediaRecord?>(
        future: _record(id),
        builder: (context, snapshot) {
          final item = snapshot.data;
          if (item == null) {
            return Center(
              child: snapshot.connectionState == ConnectionState.waiting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      '无法读取此媒体',
                      style: TextStyle(color: Colors.white70),
                    ),
            );
          }
          return MediaView(
            widget.media,
            item,
            key: ValueKey('queue-preview-media-$id'),
            autoplay: autoplay,
            controlsVisible: !zoomed,
            videoProgressBottom: 142,
          );
        },
      );

  Widget _mediaStage() {
    final width = MediaQuery.sizeOf(context).width;
    final currentId = ids[index];
    final horizontal = dragAxis == Axis.horizontal && dragOffset.dx != 0;
    final incomingIndex = index + browseDirection;
    final incomingId =
        horizontal && incomingIndex >= 0 && incomingIndex < ids.length
        ? ids[incomingIndex]
        : null;
    return _AppleZoomableMedia(
      key: ValueKey('queue-zoom-$currentId'),
      surfaceKey: const Key('queue-preview-surface'),
      viewerKey: const Key('queue-preview-zoom'),
      onSwipeUpdate: _onSwipeUpdate,
      onSwipeEnd: _onSwipeEnd,
      onSwipeCancel: () => unawaited(_returnToCenter()),
      onZoomChanged: (value) {
        if (mounted && zoomed != value) setState(() => zoomed = value);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (incomingId != null)
            Transform.translate(
              offset: Offset(
                dragOffset.dx + (browseDirection > 0 ? width : -width),
                0,
              ),
              child: _media(incomingId, autoplay: false),
            ),
          Transform.translate(
            key: const Key('queue-preview-drag-translation'),
            offset: dragOffset,
            child: _media(currentId),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.black,
    ),
    child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _mediaStage(),
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: _immersiveHeaderHeight,
            child: _SystemTopGradient(key: Key('page-top-gradient')),
          ),
          Visibility(
            visible: !zoomed,
            child: SafeArea(
              minimum: _immersiveHeaderPadding,
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: _GlassIconButton(
                      buttonKey: const Key('queue-preview-back'),
                      tooltip: '返回待删除列表',
                      icon: Icons.arrow_back_ios_new_rounded,
                      onPressed: busy
                          ? null
                          : () => Navigator.maybePop(context),
                      diameter: 44,
                      iconSize: 19,
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: _GlassSurface(
                      radius: 18,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 8,
                      ),
                      child: Text(
                        '${index + 1} / ${ids.length}',
                        key: const Key('queue-preview-counter'),
                        style: const TextStyle(
                          color: _appleGlassForeground,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _GlassSurface(
                            radius: 20,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: _appleGlassForeground,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  '左右滑动浏览 · 下滑返回',
                                  style: TextStyle(
                                    color: _appleGlassForeground,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _GlassActionButton(
                                  buttonKey: const Key('queue-preview-keep'),
                                  icon: Icons.undo_rounded,
                                  label: '保留此项',
                                  onPressed: busy
                                      ? null
                                      : () => _act(keep: true),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _GlassActionButton(
                                  buttonKey: const Key('queue-preview-delete'),
                                  icon: Icons.delete_outline_rounded,
                                  label: '删除此项',
                                  foregroundColor: _systemRed,
                                  onPressed: busy
                                      ? null
                                      : () => _act(keep: false),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen(this.app, {super.key});
  final CleanerState app;

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: const _UnifiedAppBar(title: '设置'),
    body: AnimatedBuilder(
      animation: app,
      builder: (context, _) => ListView(
        padding: EdgeInsets.fromLTRB(16, _appHeaderInset(context) + 8, 16, 28),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '下滑动作',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '修改后只影响之后的操作，已有标记会保留。',
                    style: TextStyle(color: _secondaryLabel),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<DownSwipeAction>(
                      style: ButtonStyle(
                        side: const WidgetStatePropertyAll(
                          BorderSide(color: _separator, width: 0.5),
                        ),
                        backgroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? _systemBlue
                              : Colors.transparent,
                        ),
                        foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? Colors.white
                              : _primaryLabel,
                        ),
                        textStyle: const WidgetStatePropertyAll(
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                      ),
                      segments: const [
                        ButtonSegment(
                          value: DownSwipeAction.none,
                          label: Text('无'),
                        ),
                        ButtonSegment(
                          value: DownSwipeAction.pending,
                          label: Text('待定'),
                        ),
                        ButtonSegment(
                          value: DownSwipeAction.returnToAlbum,
                          label: Text('返回相册'),
                        ),
                      ],
                      selected: {app.downAction},
                      onSelectionChanged: (values) =>
                          app.setDownAction(values.first),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 26),
          const Text(
            '权限与帮助',
            style: TextStyle(
              color: _secondaryLabel,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('管理照片权限'),
                  subtitle: Text(
                    app.permissionState == PermissionState.limited
                        ? '目前仅访问选中的媒体'
                        : '查看或调整系统授权',
                  ),
                  onTap: app.managePermission,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('重看教程'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OnboardingScreen(
                        downAction: app.downAction,
                        onDone: () async {
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('隐私说明'),
                  onTap: () => showAdaptiveDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog.adaptive(
                      title: const Text('隐私说明'),
                      content: const Text(
                        '照片和视频仅在本机读取与显示；整理标记保存在本机。删除必须经过队列复核和系统确认。',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('好'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          const Text(
            '本地数据',
            style: TextStyle(
              color: _secondaryLabel,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.restart_alt, color: _systemRed),
              title: const Text(
                '清除本地整理记录',
                style: TextStyle(color: _systemRed),
              ),
              subtitle: const Text('不会删除系统照片'),
              onTap: () async {
                final accepted = await showAdaptiveDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog.adaptive(
                    title: const Text('清除本地记录？'),
                    content: const Text('将清除进度、待定、保留和待删除标记，不会删除系统照片。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: _systemRed,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('清除记录'),
                      ),
                    ],
                  ),
                );
                if (accepted == true) await app.store.clearRecords();
              },
            ),
          ),
        ],
      ),
    ),
  );
}
