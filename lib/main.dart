import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import 'media_repository.dart';
import 'store.dart';

enum DownSwipeAction { none, pending, returnToAlbum, skip }

extension on DownSwipeAction {
  ReviewAction? get reviewAction => switch (this) {
    DownSwipeAction.none => null,
    DownSwipeAction.pending => ReviewAction.pending,
    DownSwipeAction.returnToAlbum => null,
    DownSwipeAction.skip => ReviewAction.skip,
  };

  String get label => switch (this) {
    DownSwipeAction.none => '无',
    DownSwipeAction.pending => '待定',
    DownSwipeAction.returnToAlbum => '返回相册',
    DownSwipeAction.skip => '跳过',
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await AppStore.open();
  runApp(CleanerApp(CleanerState(store, MediaRepository())));
}

class CleanerState extends ChangeNotifier {
  CleanerState(this.store, this.media);
  final AppStore store;
  final MediaRepository media;
  bool ready = false;
  bool onboarded = false;
  bool scanning = false;
  bool scanFailed = false;
  int indexed = 0;
  PermissionState? permissionState;
  DownSwipeAction downAction = DownSwipeAction.returnToAlbum;
  List<(String, int)> months = [];

  Future<void> initialize() async {
    onboarded = await store.setting('onboarded') == '1';
    downAction = switch (await store.setting('down_swipe_action')) {
      'pending' || 'undecided' => DownSwipeAction.pending,
      'keep' || 'returnToAlbum' => DownSwipeAction.returnToAlbum,
      'skip' => DownSwipeAction.skip,
      'none' => DownSwipeAction.none,
      _ => DownSwipeAction.returnToAlbum,
    };
    permissionState = await media.permission();
    ready = true;
    notifyListeners();
    if (onboarded && permissionState!.hasAccess) await refresh();
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
    indexed = 0;
    notifyListeners();
    try {
      await media.scan(store, (count) {
        indexed = count;
        notifyListeners();
      });
      months = await store.months();
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
    widget.state.initialize();
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
    title: '相册清理',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1557F8),
        primary: const Color(0xFF1557F8),
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFF7F8FA),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF7F8FA),
        foregroundColor: Color(0xFF10131A),
        elevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w800,
          color: Color(0xFF10131A),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      useMaterial3: true,
    ),
    home: AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final app = widget.state;
        if (!app.ready) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
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

class _OnboardingScreenState extends State<OnboardingScreen> {
  final pages = const [
    ('一张张整理相册', '只浏览你允许访问的照片和视频，随时可以停下。', Icons.photo_library_outlined),
    ('左右切换', '左滑上一张，右滑下一张；浏览本身不做决定。', Icons.swipe_outlined),
    ('先标记，再复核', '上滑只加入待删除队列，不会立即删除系统照片。', Icons.swipe_up_outlined),
    ('认真复核', '从队列移出误选照片，确认后才请求系统处理。', Icons.fact_check_outlined),
    ('授权访问照片', '可以允许全部或部分照片；只处理当前授权范围。', Icons.lock_outline),
  ];
  final PageController pager = PageController();
  int page = 0;
  bool busy = false;

  @override
  void dispose() {
    pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.downAction.label;
    return Scaffold(
      appBar: AppBar(title: const Text('使用说明')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: pager,
                itemCount: pages.length,
                onPageChanged: (value) => setState(() => page = value),
                itemBuilder: (context, index) {
                  final (title, body, icon) = pages[index];
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 96,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 32),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          index == 2 ? '$body\n下滑当前为“$action”，可在设置中更改。' : body,
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Text('${page + 1} / ${pages.length}'),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (page > 0)
                    TextButton(
                      onPressed: () => pager.previousPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                      child: const Text('上一页'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (page < pages.length - 1) {
                              pager.nextPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              );
                            } else {
                              setState(() => busy = true);
                              try {
                                await widget.onDone();
                              } finally {
                                if (mounted) setState(() => busy = false);
                              }
                            }
                          },
                    child: Text(page == pages.length - 1 ? '开始并授权' : '下一页'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PermissionScreen extends StatelessWidget {
  const PermissionScreen(this.app, {super.key});
  final CleanerState app;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('照片访问权限')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 72),
            const SizedBox(height: 20),
            const Text(
              '需要照片访问权限才能整理相册。你也可以只选择部分照片。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: app.requestPermission,
              child: const Text('请求照片权限'),
            ),
            TextButton(
              onPressed: app.managePermission,
              child: const Text('前往系统设置'),
            ),
          ],
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
  int albumMode = 0;
  String? selectedYear;
  late Future<List<SystemAlbumSummary>> systemAlbums;
  late Future<List<SystemCategorySummary>> systemCategories;
  MediaStorageSummary? storage;
  bool storageLoading = false;
  int storageProcessed = 0;
  int storageTotal = 0;

  CleanerState get app => widget.app;

  @override
  void initState() {
    super.initState();
    systemAlbums = app.media.systemAlbums();
    systemCategories = app.media.systemCategories();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() {});
  }

  Future<void> _calculateStorage() async {
    if (storageLoading || storage != null) return;
    setState(() => storageLoading = true);
    try {
      final result = await app.media.storageSummary((processed, total) {
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
    setState(() {
      systemAlbums = app.media.systemAlbums();
      systemCategories = app.media.systemCategories();
      storage = null;
      storageProcessed = 0;
      storageTotal = 0;
    });
    if (tab == 2) await _calculateStorage();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    final gb = bytes / (1024 * 1024 * 1024);
    if (gb >= 1) return '${gb.toStringAsFixed(gb >= 10 ? 1 : 2)} GB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }

  Widget _sectionTitle(String title, {String? subtitle}) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 26, 2, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF7F8490)),
            ),
          ),
      ],
    ),
  );

  Widget _scopeTile(
    Scope scope,
    IconData icon, {
    int? knownCount,
    String? title,
    bool cornerLabels = false,
  }) => FutureBuilder<int>(
    future: knownCount == null
        ? app.store.count(scope)
        : Future.value(knownCount),
    builder: (context, count) => InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => _open(ScopeScreen(app, scope)),
      child: Container(
        height: 145,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFECEEF2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if ((count.data ?? 0) > 0)
              FutureBuilder<MediaRecord?>(
                future: app.store.at(scope, 0),
                builder: (context, first) => first.data == null
                    ? const SizedBox.shrink()
                    : MediaThumb(app.media, first.data!.id),
              ),
            if (!cornerLabels || (count.data ?? 0) == 0)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: (count.data ?? 0) > 0
                        ? [Colors.black12, Colors.black.withValues(alpha: 0.65)]
                        : [const Color(0xFFF6F8FF), const Color(0xFFEEF2FF)],
                  ),
                ),
              ),
            if (cornerLabels) ...[
              Positioned(
                left: 14,
                top: 14,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      color: (count.data ?? 0) > 0
                          ? Colors.white
                          : const Color(0xFF1557F8),
                      shadows: (count.data ?? 0) > 0
                          ? const [
                              Shadow(
                                color: Color(0xB3000000),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      title ?? scope.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: (count.data ?? 0) > 0
                            ? Colors.white
                            : const Color(0xFF10131A),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        shadows: (count.data ?? 0) > 0
                            ? const [
                                Shadow(
                                  color: Color(0xB3000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 14,
                bottom: 14,
                child: Text(
                  count.hasData ? '${count.data} 项' : '读取中',
                  style: TextStyle(
                    color: (count.data ?? 0) > 0
                        ? Colors.white
                        : const Color(0xFF818895),
                    fontWeight: FontWeight.w700,
                    shadows: (count.data ?? 0) > 0
                        ? const [
                            Shadow(
                              color: Color(0xB3000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(
                      icon,
                      color: (count.data ?? 0) > 0
                          ? Colors.white
                          : const Color(0xFF1557F8),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title ?? scope.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: (count.data ?? 0) > 0
                                ? Colors.white
                                : const Color(0xFF10131A),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          count.hasData ? '${count.data} 项' : '读取中',
                          style: TextStyle(
                            color: (count.data ?? 0) > 0
                                ? Colors.white70
                                : const Color(0xFF818895),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _tileGrid(List<Widget> children) => GridView.count(
    crossAxisCount: 2,
    crossAxisSpacing: 12,
    mainAxisSpacing: 12,
    childAspectRatio: 1.25,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    children: children,
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
          child: Icon(Icons.delete_outline, color: Color(0xFF1557F8)),
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

  Widget _reviewHero() => FutureBuilder<ReviewProgress?>(
    future: app.store.reviewProgress(Scope.all),
    builder: (context, progressSnapshot) => FutureBuilder<int>(
      future: app.store.count(Scope.all),
      builder: (context, countSnapshot) {
        final progress = progressSnapshot.data;
        final total = countSnapshot.data ?? progress?.total;
        final hasProgress = progress != null && progress.total > 0;
        final lastTime = hasProgress
            ? DateTime.fromMillisecondsSinceEpoch(progress.updatedAt).toLocal()
            : null;
        final enabled = total != 0;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            key: const Key('review-hero'),
            borderRadius: BorderRadius.circular(24),
            onTap: enabled
                ? () => _open(ScopeScreen(app, Scope.all, startReview: true))
                : null,
            child: Ink(
              height: 128,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFDCE5FF)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1557F8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.photo_library_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasProgress ? '继续整理' : '开始整理',
                          style: const TextStyle(
                            color: Color(0xFF10131A),
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          hasProgress
                              ? '上次到第 ${progress.position + 1} / ${progress.total} 项'
                                    ' · ${lastTime!.month}月${lastTime.day}日'
                              : total == null
                              ? '正在读取相册'
                              : '当前可整理 $total 项照片与视频',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF687086),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: enabled
                          ? const Color(0xFF1557F8)
                          : const Color(0xFFD8DDE8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  String _categoryLabel(SystemCategoryKind kind) => switch (kind) {
    SystemCategoryKind.videos => '视频',
    SystemCategoryKind.screenshots => '截屏',
    SystemCategoryKind.live => '实况',
    SystemCategoryKind.selfies => '自拍',
    SystemCategoryKind.portraits => '人像',
    SystemCategoryKind.spatialPhotos => '空间照片',
    SystemCategoryKind.spatialVideos => '空间视频',
  };

  IconData _categoryIcon(SystemCategoryKind kind) => switch (kind) {
    SystemCategoryKind.videos => Icons.play_circle_outline,
    SystemCategoryKind.screenshots => Icons.screenshot_outlined,
    SystemCategoryKind.live => Icons.motion_photos_on_outlined,
    SystemCategoryKind.selfies => Icons.face_outlined,
    SystemCategoryKind.portraits => Icons.portrait_outlined,
    SystemCategoryKind.spatialPhotos => Icons.view_in_ar_outlined,
    SystemCategoryKind.spatialVideos => Icons.videocam_outlined,
  };

  Widget _systemCategoryTile(SystemCategorySummary category) {
    final label = _categoryLabel(category.kind);
    return InkWell(
      borderRadius: BorderRadius.circular(22),
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
          assetType: category.assetType,
        ),
      ),
      child: Container(
        height: 145,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F6FF),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFECEEF2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(_categoryIcon(category.kind), color: const Color(0xFF1557F8)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${category.count} 项',
                  style: const TextStyle(color: Color(0xFF818895)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryGrid() {
    if (!Platform.isIOS) {
      return _tileGrid([
        _scopeTile(Scope.all, Icons.photo_library_outlined),
        _scopeTile(Scope.videos, Icons.play_circle_outline),
        _scopeTile(Scope.screenshots, Icons.screenshot_outlined),
      ]);
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
        if (categories.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text(
              '系统没有返回可用分类',
              style: TextStyle(color: Color(0xFF818895)),
            ),
          );
        }
        return _tileGrid([
          _scopeTile(Scope.all, Icons.photo_library_outlined),
          ...categories.map(_systemCategoryTile),
        ]);
      },
    );
  }

  Widget _home() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
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
      _reviewHero(),
      _sectionTitle('分类整理'),
      _categoryGrid(),
      _sectionTitle('整理进度'),
      _queueCard(),
      if (Platform.isAndroid)
        const Padding(
          padding: EdgeInsets.only(top: 18),
          child: Text(
            '自拍和动态照片在 Android 上没有统一的可靠标记，可在“全部”中查看。',
            style: TextStyle(color: Color(0xFF818895), fontSize: 12),
          ),
        ),
    ],
  );

  Widget _albumCard(SystemAlbumSummary album) => InkWell(
    borderRadius: BorderRadius.circular(24),
    onTap: () => _open(SystemAlbumScreen(app, album)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AspectRatio(
            aspectRatio: 1.2,
            child: album.coverId == null
                ? const ColoredBox(
                    color: Color(0xFFEAF0FF),
                    child: Icon(
                      Icons.photo_library_outlined,
                      color: Color(0xFF1557F8),
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
          style: const TextStyle(color: Color(0xFF818895), fontSize: 12),
        ),
      ],
    ),
  );

  Widget _albumGrid(String title, List<SystemAlbumSummary> albums, {Key? key}) {
    if (albums.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title),
        GridView.builder(
          key: key,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: albums.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
            childAspectRatio: 0.9,
          ),
          itemBuilder: (context, index) => _albumCard(albums[index]),
        ),
      ],
    );
  }

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
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
        children: [
          SizedBox(
            height: 150,
            child: _scopeTile(Scope.all, Icons.photo_library_outlined),
          ),
          if (snapshot.connectionState == ConnectionState.waiting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: Center(child: CircularProgressIndicator()),
            ),
          _albumGrid('手机相册', personal, key: const Key('system-album-grid')),
          _albumGrid('人物', people),
          _albumGrid('系统分类', smart),
          if (!Platform.isIOS) ...[
            _sectionTitle('媒体类型'),
            _tileGrid([
              _scopeTile(Scope.screenshots, Icons.screenshot_outlined),
              _scopeTile(Scope.videos, Icons.play_circle_outline),
            ]),
          ],
          _sectionTitle('待删除'),
          _queueCard(),
        ],
      );
    },
  );

  Widget _yearMonth() {
    final years = app.months
        .map((row) => row.$1 == 'unknown' ? '时间未知' : row.$1.substring(0, 4))
        .toSet()
        .toList();
    if (years.isEmpty) return const Center(child: Text('还没有可浏览的媒体'));
    final activeYear = years.contains(selectedYear)
        ? selectedYear!
        : years.first;
    final months = app.months.where((row) {
      final year = row.$1 == 'unknown' ? '时间未知' : row.$1.substring(0, 4);
      return year == activeYear;
    }).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 16, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: ListView.separated(
              itemCount: years.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final year = years[index];
                final selected = year == activeYear;
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => setState(() => selectedYear = year),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF1557F8)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      year,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : const Color(0xFF818895),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GridView.builder(
              itemCount: months.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.04,
              ),
              itemBuilder: (context, index) {
                final row = months[index];
                return _scopeTile(
                  Scope.month(row.$1),
                  Icons.calendar_month_outlined,
                  knownCount: row.$2,
                  title: row.$1 == 'unknown'
                      ? '时间未知'
                      : '${int.parse(row.$1.substring(5, 7))}月',
                  cornerLabels: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _albums() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('分类')),
            ButtonSegment(value: 1, label: Text('年月')),
          ],
          selected: {albumMode},
          showSelectedIcon: false,
          onSelectionChanged: (value) =>
              setState(() => albumMode = value.first),
          style: const ButtonStyle(visualDensity: VisualDensity(vertical: 2)),
        ),
      ),
      Expanded(child: albumMode == 0 ? _albumCategories() : _yearMonth()),
    ],
  );

  Widget _storageOverview() => Card(
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
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          if (storageLoading)
            LinearProgressIndicator(
              value: storageTotal == 0 ? null : storageProcessed / storageTotal,
              borderRadius: BorderRadius.circular(8),
            )
          else if (storage != null && storage!.totalBytes > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  if (storage!.photoBytes > 0)
                    Expanded(
                      flex: storage!.photoBytes,
                      child: const ColoredBox(
                        color: Color(0xFF1557F8),
                        child: SizedBox(height: 14),
                      ),
                    ),
                  if (storage!.videoBytes > 0)
                    Expanded(
                      flex: storage!.videoBytes,
                      child: const ColoredBox(
                        color: Color(0xFFFF9B37),
                        child: SizedBox(height: 14),
                      ),
                    ),
                  if (storage!.screenshotBytes > 0)
                    Expanded(
                      flex: storage!.screenshotBytes,
                      child: const ColoredBox(
                        color: Color(0xFF7C4DFF),
                        child: SizedBox(height: 14),
                      ),
                    ),
                  if (storage!.liveBytes > 0)
                    Expanded(
                      flex: storage!.liveBytes,
                      child: const ColoredBox(
                        color: Color(0xFF2F8A67),
                        child: SizedBox(height: 14),
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
                  '照片',
                  storage?.photoBytes,
                  const Color(0xFF1557F8),
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: _storageMetric(
                  '视频',
                  storage?.videoBytes,
                  const Color(0xFFFF9B37),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _storageMetric(
                  '截图',
                  storage?.screenshotBytes,
                  const Color(0xFF7C4DFF),
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: _storageMetric(
                  '实况',
                  storage?.liveBytes,
                  const Color(0xFF2F8A67),
                ),
              ),
            ],
          ),
          if (storage?.unknownItems case final unknown? when unknown > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '$unknown 项暂时无法取得大小，以上为当前授权范围的估算值。',
                style: const TextStyle(color: Color(0xFF818895), fontSize: 12),
              ),
            ),
        ],
      ),
    ),
  );

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
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ],
  );

  Widget _more() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
    children: [
      _storageOverview(),
      _sectionTitle('待处理'),
      _queueCard(),
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
          style: TextStyle(color: Color(0xFF818895), fontSize: 12),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: const Color(0xFFF7F8FA),
      systemStatusBarContrastEnforced: false,
    ),
    child: Scaffold(
      body: SafeArea(
        child: app.scanning && app.months.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('正在读取相册索引：${app.indexed} 项'),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _refreshAll,
                child: [_home(), _albums(), _more()][tab],
              ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: NavigationBar(
              height: 70,
              selectedIndex: tab,
              onDestinationSelected: (index) {
                setState(() => tab = index);
                if (index == 2) _calculateStorage();
              },
              backgroundColor: Colors.white,
              indicatorColor: const Color(0xFFE7ECFF),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: '首页',
                ),
                NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view_rounded),
                  label: '相册',
                ),
                NavigationDestination(
                  icon: Icon(Icons.more_horiz),
                  label: '更多',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class SystemAlbumScreen extends StatefulWidget {
  const SystemAlbumScreen(
    this.app,
    this.album, {
    super.key,
    this.title,
    this.assetType,
  });

  final CleanerState app;
  final SystemAlbumSummary album;
  final String? title;
  final AssetType? assetType;

  @override
  State<SystemAlbumScreen> createState() => _SystemAlbumScreenState();
}

class _SystemAlbumScreenState extends State<SystemAlbumScreen> {
  List<MediaRecord>? records;
  int loaded = 0;
  int total = 0;

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
    }, assetType: widget.assetType);
    if (mounted) setState(() => records = result);
  }

  Future<void> _review([int? initialIndex]) async {
    final items = records;
    if (items == null || items.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          widget.app,
          Scope(
            'album:${widget.album.path.id}'
            '${widget.assetType == null ? '' : ':${widget.assetType!.name}'}',
            widget.title ??
                (widget.album.path.name.trim().isEmpty
                    ? '未命名相册'
                    : widget.album.path.name),
          ),
          initialIndex: initialIndex,
          source: items,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.title ??
            (widget.album.path.name.trim().isEmpty
                ? '未命名相册'
                : widget.album.path.name),
      ),
    ),
    body: records == null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 14),
                Text('正在读取 $loaded / $total 项'),
              ],
            ),
          )
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                child: Row(
                  children: [
                    Text(
                      '${records!.length} 项媒体',
                      style: const TextStyle(color: Color(0xFF818895)),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: records!.isEmpty ? null : _review,
                      child: const Text('开始整理'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: records!.isEmpty
                    ? const Center(child: Text('这个相册没有可访问的媒体'))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                            ),
                        itemCount: records!.length,
                        itemBuilder: (context, index) => ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: InkWell(
                            onTap: () => _review(index),
                            child: MediaThumb(
                              widget.app.media,
                              records![index].id,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
  );
}

class ScopeScreen extends StatefulWidget {
  const ScopeScreen(
    this.app,
    this.scope, {
    super.key,
    this.startReview = false,
  });
  final CleanerState app;
  final Scope scope;
  final bool startReview;

  @override
  State<ScopeScreen> createState() => _ScopeScreenState();
}

class _ScopeScreenState extends State<ScopeScreen> {
  final ScrollController gridController = ScrollController();
  bool pendingOnly = false;
  bool reviewStarted = false;
  int count = 0;
  int? focusedIndex;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    gridController.dispose();
    super.dispose();
  }

  Future<void> _refresh({String? focusId}) async {
    final total = await widget.app.store.count(
      widget.scope,
      pendingOnly: pendingOnly,
    );
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
      focusedIndex = focus != null && focus >= 0 ? focus : null;
    });
    if (focusedIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !gridController.hasClients) return;
        final lastRow = (count - 1) ~/ 4;
        final row = focusedIndex! ~/ 4;
        final offset = lastRow == 0
            ? 0.0
            : gridController.position.maxScrollExtent * row / lastRow;
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
    final focusId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          widget.app,
          widget.scope,
          initialIndex: index,
          pendingOnly: pendingOnly,
        ),
      ),
    );
    await _refresh(focusId: focusId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.scope.label),
      actions: [
        TextButton(
          onPressed: () {
            setState(() => pendingOnly = !pendingOnly);
            _refresh();
          },
          child: Text(pendingOnly ? '查看全部' : '只看待定'),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '$count 项媒体',
              style: const TextStyle(color: Color(0xFF818895)),
            ),
          ),
        ),
        Expanded(
          child: count == 0
              ? const Center(child: Text('这里还没有可浏览的媒体'))
              : GridView.builder(
                  controller: gridController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: count,
                  itemBuilder: (context, index) => FutureBuilder<MediaRecord?>(
                    future: widget.app.store.at(
                      widget.scope,
                      index,
                      pendingOnly: pendingOnly,
                    ),
                    builder: (context, snapshot) {
                      final item = snapshot.data;
                      if (item == null) {
                        return const ColoredBox(color: Color(0xFFE7ECEB));
                      }
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          onTap: () => _open(index),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              MediaThumb(widget.app.media, item.id),
                              const Align(
                                alignment: Alignment.bottomCenter,
                                child: SizedBox(
                                  height: 48,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.black54,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 12,
                                bottom: 10,
                                child: Text(
                                  item.takenAt == 0
                                      ? '时间未知'
                                      : DateTime.fromMillisecondsSinceEpoch(
                                          item.takenAt,
                                        ).toLocal().toString().substring(0, 10),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (item.type == 2)
                                const Positioned(
                                  right: 10,
                                  top: 10,
                                  child: Icon(
                                    Icons.play_circle_fill,
                                    color: Colors.white,
                                  ),
                                ),
                              if (focusedIndex == index)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: DecoratedBox(
                                      key: Key('focused-scope-item-$index'),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
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
                    },
                  ),
                ),
        ),
      ],
    ),
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
  });
  final CleanerState app;
  final Scope scope;
  final int? initialIndex;
  final bool pendingOnly;
  final List<MediaRecord>? source;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen>
    with SingleTickerProviderStateMixin {
  static const reviewBackground = Color(0xFFF3F4F6);

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
  double scaleStartZoom = 1;
  Offset zoomOffset = Offset.zero;
  Offset doubleTapPosition = Offset.zero;
  final ValueNotifier<int> gestureFrame = ValueNotifier(0);
  late final AnimationController motion;
  late Animation<Offset> motionAnimation;
  late Animation<double> scaleAnimation;

  @override
  void initState() {
    super.initState();
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
    motion.dispose();
    gestureFrame.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    total =
        widget.source?.length ??
        await widget.app.store.count(
          widget.scope,
          pendingOnly: widget.pendingOnly,
        );
    queueCount = (await widget.app.store.queue()).length;
    if (widget.initialIndex != null) {
      index = widget.initialIndex!;
    } else if (!widget.pendingOnly) {
      final anchor = await widget.app.store.anchor(widget.scope);
      if (anchor != null) {
        index = widget.source == null
            ? await widget.app.store.positionOf(widget.scope, anchor)
            : widget.source!.indexWhere((item) => item.id == anchor);
        if (index < 0) index = 0;
      }
    }
    if (index >= total && total > 0) index = total - 1;
    await _load();
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
      zoomOffset = Offset.zero;
      actionScale = 1;
      dragAxis = null;
      panOffset = Offset.zero;
    });
    if (item != null) await widget.app.store.saveAnchor(widget.scope, item);
    _prefetchAround(index);
  }

  Future<MediaRecord?> _itemAt(int target) async {
    if (target < 0 || target >= total) return null;
    return widget.source == null
        ? widget.app.store.at(
            widget.scope,
            target,
            pendingOnly: widget.pendingOnly,
          )
        : widget.source![target];
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
  }) async {
    final distance = (target - dragOffset).distance;
    motion.duration = velocity <= 0
        ? const Duration(milliseconds: 170)
        : Duration(
            milliseconds: (distance / velocity * 1000).round().clamp(90, 170),
          );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(next < 0 ? '已经是第一张' : '已经是最后一张，可以向右滑动返回上一张')),
      );
      return;
    }
    setState(() => busy = true);
    try {
      browseDirection = amount;
      final cachedItem = amount > 0 ? nextItem : previousItem;
      final cachedPreview = amount > 0 ? nextPreview : previousPreview;
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
          zoomOffset = Offset.zero;
          actionScale = 1;
          dragAxis = null;
          panOffset = Offset.zero;
        });
      }
      await widget.app.store.saveAnchor(widget.scope, loadedItem);
      _prefetchAround(index);
    } finally {
      if (mounted) setState(() => busy = false);
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
      total =
          widget.source?.length ??
          await widget.app.store.count(
            widget.scope,
            pendingOnly: widget.pendingOnly,
          );
      final removedFromView =
          widget.pendingOnly &&
          action != ReviewAction.pending &&
          action != ReviewAction.skip;
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
          zoomOffset = Offset.zero;
          actionScale = 1;
          dragAxis = null;
          panOffset = Offset.zero;
        });
      }
      if (loadedItem != null) {
        await widget.app.store.saveAnchor(widget.scope, loadedItem);
      }
      _prefetchAround(index);
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  void _onPanUpdate(Offset delta) {
    if (busy || current == null) return;
    panOffset += delta;
    if (dragAxis == null && panOffset.distance < 8) return;
    dragAxis ??= panOffset.dx.abs() >= panOffset.dy.abs()
        ? Axis.horizontal
        : Axis.vertical;
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

  Future<void> _onPanEnd(Velocity velocity) async {
    if (busy || current == null) return;
    if (dragAxis == Axis.vertical && dragOffset.dy.abs() >= 86) {
      if (dragOffset.dy > 0 &&
          widget.app.downAction == DownSwipeAction.returnToAlbum) {
        setState(() => busy = true);
        await _animateTo(
          Offset(0, MediaQuery.sizeOf(context).height * 1.08),
          velocity: velocity.pixelsPerSecond.dy.abs(),
        );
        if (!mounted) return;
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop(current?.id);
        } else {
          setState(() => busy = false);
          await _returnToCenter(velocity: velocity.pixelsPerSecond.dy.abs());
        }
        return;
      }
      final action = dragOffset.dy < 0
          ? ReviewAction.delete
          : widget.app.downAction.reviewAction;
      if (action == null) {
        await _returnToCenter(velocity: velocity.pixelsPerSecond.dy.abs());
      } else {
        await _act(action, velocity: velocity.pixelsPerSecond.dy.abs());
      }
      return;
    }
    if (dragAxis == Axis.horizontal && dragOffset.dx.abs() >= 72) {
      await _move(
        dragOffset.dx < 0 ? 1 : -1,
        velocity: velocity.pixelsPerSecond.dx.abs(),
      );
      return;
    }
    await _returnToCenter(velocity: velocity.pixelsPerSecond.distance);
  }

  void _onScaleStart(ScaleStartDetails details) {
    scaleStartZoom = zoom;
    if (zoom == 1) {
      dragAxis = null;
      panOffset = Offset.zero;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (busy || current == null) return;
    if (details.pointerCount == 1 && zoom == 1 && details.scale == 1) {
      _onPanUpdate(details.focalPointDelta);
      return;
    }
    final size = MediaQuery.sizeOf(context);
    final nextZoom = (scaleStartZoom * details.scale).clamp(1.0, 4.0);
    final scaleChange = nextZoom / zoom;
    final focalPoint =
        details.localFocalPoint - Offset(size.width / 2, size.height / 2);
    var nextOffset =
        (zoomOffset - focalPoint) * scaleChange +
        focalPoint +
        details.focalPointDelta;
    if (nextZoom == 1) {
      nextOffset = Offset.zero;
    } else {
      final maxX = size.width * (nextZoom - 1) / 2;
      final maxY = size.height * (nextZoom - 1) / 2;
      nextOffset = Offset(
        nextOffset.dx.clamp(-maxX, maxX).toDouble(),
        nextOffset.dy.clamp(-maxY, maxY).toDouble(),
      );
    }
    zoom = nextZoom;
    zoomOffset = nextOffset;
    dragOffset = Offset.zero;
    dragAxis = null;
    panOffset = Offset.zero;
    gestureFrame.value++;
  }

  Future<void> _onScaleEnd(ScaleEndDetails details) async {
    if (zoom > 1) return;
    await _onPanEnd(details.velocity);
  }

  void _onDoubleTap() {
    final size = MediaQuery.sizeOf(context);
    setState(() {
      if (zoom > 1) {
        zoom = 1;
        zoomOffset = Offset.zero;
      } else {
        zoom = 2.5;
        final focalPoint =
            doubleTapPosition - Offset(size.width / 2, size.height / 2);
        zoomOffset = focalPoint * (1 - zoom);
      }
      dragOffset = Offset.zero;
      dragAxis = null;
      panOffset = Offset.zero;
    });
  }

  Future<void> _undo() async {
    if (busy || undoHistory.isEmpty) return;
    setState(() => busy = true);
    try {
      final snapshot = undoHistory.last;
      await widget.app.store.undo(snapshot);
      undoHistory.removeLast();
      queueCount = (await widget.app.store.queue()).length;
      total =
          widget.source?.length ??
          await widget.app.store.count(
            widget.scope,
            pendingOnly: widget.pendingOnly,
          );
      index = widget.source == null
          ? await widget.app.store.positionOf(
              widget.scope,
              snapshot.mediaId,
              pendingOnly: widget.pendingOnly,
            )
          : widget.source!.indexWhere((item) => item.id == snapshot.mediaId);
      if (index < 0) index = 0;
      await _load();
    } finally {
      if (mounted) setState(() => busy = false);
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

  Widget _mediaStage(MediaRecord item) => GestureDetector(
    key: const Key('review-gesture'),
    behavior: HitTestBehavior.opaque,
    onScaleStart: _onScaleStart,
    onScaleUpdate: _onScaleUpdate,
    onScaleEnd: _onScaleEnd,
    onDoubleTapDown: (details) => doubleTapPosition = details.localPosition,
    onDoubleTap: _onDoubleTap,
    child: ValueListenableBuilder<int>(
      valueListenable: gestureFrame,
      builder: (context, _, _) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final horizontalTransition =
            dragOffset.dx.abs() > dragOffset.dy.abs() && dragOffset.dx != 0;
        final horizontalProgress = horizontalTransition
            ? (dragOffset.dx.abs() / screenWidth).clamp(0.0, 1.0)
            : 1.0;
        final incomingScale = 0.86 + horizontalProgress * 0.14;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (incoming != null)
              Opacity(
                key: const Key('incoming-media-opacity'),
                opacity: horizontalProgress,
                child: Transform.scale(
                  key: const Key('incoming-media-scale'),
                  scale: incomingScale,
                  child: MediaView(
                    widget.app.media,
                    incoming!,
                    key: ValueKey('incoming-${incoming!.id}'),
                    autoplay: false,
                    previewBytes: incomingPreview,
                  ),
                ),
              ),
            Transform.translate(
              key: const Key('media-drag-translation'),
              offset: dragOffset,
              child: Transform.scale(
                key: const Key('action-media-scale'),
                scale: actionScale,
                child: Transform.rotate(
                  angle: dragOffset.dx / screenWidth * 0.045,
                  child: Transform.translate(
                    offset: zoomOffset,
                    child: Transform.scale(
                      scale: zoom,
                      child: MediaView(
                        widget.app.media,
                        item,
                        key: ValueKey(item.id),
                        previewBytes: currentPreview,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final item = current;
    return AnnotatedRegion<SystemUiOverlayStyle>(
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
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            else
              _mediaStage(item),
            SafeArea(
              minimum: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: _glassIcon(
                      tooltip: '返回',
                      icon: Icons.arrow_back_ios_new_rounded,
                      onPressed: busy
                          ? null
                          : () => Navigator.pop(context, current?.id),
                      diameter: 40,
                      iconSize: 19,
                      color: const Color(0x2E000000),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: _glass(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 8,
                      ),
                      color: const Color(0x2E000000),
                      child: Text(
                        item == null
                            ? '$total / $total'
                            : '${index + 1} / $total',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
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
                                    dragOffset.dy.abs() > dragOffset.dx.abs()
                                ? (dragOffset.dy.abs() / 86).clamp(0.0, 1.0)
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
                                diameter: 40,
                                iconSize: 20,
                                color: Color.lerp(
                                  const Color(0x2E000000),
                                  const Color(0xE6DC3D55),
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
                                color: const Color(0xFFDC3D55),
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
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                              : const Color(0x2E000000),
                        ),
                        const SizedBox(width: 12),
                        _glassIcon(
                          key: const Key('undo-control'),
                          tooltip: '撤销上一步',
                          icon: Icons.undo_rounded,
                          onPressed: busy || undoHistory.isEmpty ? null : _undo,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glass({
    required Widget child,
    required EdgeInsets padding,
    Color color = const Color(0x4DFFFFFF),
  }) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26000000),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );

  Widget _glassIcon({
    Key? key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    double diameter = 48,
    double iconSize = 22,
    Color color = const Color(0x4DFFFFFF),
  }) => _glass(
    padding: EdgeInsets.zero,
    color: color,
    child: IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      color: Colors.white,
      disabledColor: Colors.white38,
      constraints: BoxConstraints.tightFor(width: diameter, height: diameter),
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: iconSize),
    ),
  );
}

class MediaView extends StatefulWidget {
  const MediaView(
    this.media,
    this.item, {
    super.key,
    this.previewBytes,
    this.autoplay = true,
  });
  final MediaRepository media;
  final MediaRecord item;
  final Uint8List? previewBytes;
  final bool autoplay;

  @override
  State<MediaView> createState() => _MediaViewState();
}

class _MediaViewState extends State<MediaView> {
  VideoPlayerController? player;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.item.type == 2 && widget.autoplay) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    }
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    if (loading) return;
    if (player != null) {
      player!.value.isPlaying ? await player!.pause() : await player!.play();
      setState(() {});
      return;
    }
    setState(() => loading = true);
    try {
      final file = await widget.media.videoFile(widget.item.id);
      if (file == null) throw StateError('视频不可访问');
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      player = controller;
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

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

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
          const LinearProgressIndicator(
            value: 0,
            minHeight: 4,
            color: Colors.white,
            backgroundColor: Colors.white38,
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
          VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            padding: const EdgeInsets.only(top: 5, bottom: 8),
            colors: const VideoProgressColors(
              playedColor: Colors.white,
              bufferedColor: Colors.white54,
              backgroundColor: Colors.white24,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = player?.value.isInitialized == true
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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Color(0x66000000),
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
                if (widget.item.type == 2)
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
                if (widget.item.type == 2)
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 10,
                    child: DefaultTextStyle(
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                      ),
                      child: _videoProgress(),
                    ),
                  ),
              ],
            ),
          ),
        ),
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
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _restore(Iterable<String> ids) async {
    if (busy) return;
    final restored = ids.toSet();
    if (restored.isEmpty) return;
    setState(() => busy = true);
    try {
      for (final id in restored) {
        await widget.app.store.removeFromQueue(id);
      }
      selected.removeAll(restored);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已恢复 ${restored.length} 项')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _openPreview(String id) async {
    final asset = await widget.app.media.get(id);
    if (asset == null || !mounted) return;
    final media = MediaRecord(
      id: id,
      takenAt: asset.createDateSecond == null
          ? 0
          : asset.createDateSecond! * 1000,
      month: 'unknown',
      type: asset.type == AssetType.video ? 2 : 1,
      duration: asset.duration,
      screenshot: false,
      selfie: false,
      live: asset.isLivePhoto,
    );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QueuePreviewScreen(widget.app.media, media),
      ),
    );
  }

  Future<void> _process() async {
    if (busy || selected.isEmpty) return;
    final ids = selected.toList();
    final usesTrash = await widget.app.media.usesRecoverableTrash();
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${ids.length} 项？'),
        content: Text(
          Platform.isIOS
              ? '将再次弹出系统确认。iCloud 照片开启时，删除也可能同步到同一 Apple 账户的其他设备。移入最近删除不等于立即释放空间。'
              : usesTrash
              ? '将再次弹出系统确认。媒体将移入设备回收站，具体保留时间由系统决定；移入回收站不等于立即释放空间。'
              : 'Android 10 不提供统一的媒体回收站。确认后将永久删除所选媒体，此操作无法在本应用中恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回复核'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续删除'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => busy = true);
    try {
      final result = await widget.app.media.deleteReviewedMedia(
        widget.app.store,
        ids,
      );
      await widget.app.refresh();
      await _load();
      if (!mounted) return;
      final counts = <String, int>{};
      for (final status in result.values) {
        counts[status] = (counts[status] ?? 0) + 1;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('处理结果'),
          content: Text(
            '${usesTrash ? '已移入系统最近删除/回收站' : '已删除'}：${counts['confirmedRemoved'] ?? 0}\n'
            '取消：${counts['cancelled'] ?? 0} · 不可访问：${counts['missing'] ?? 0}\n'
            '待核对：${counts['unknown'] ?? 0}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('系统处理未完成，请检查权限并在队列中核对状态。')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('待删除队列'),
      actions: [
        TextButton(
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
          child: Text(
            rows.isNotEmpty && selected.length == rows.length ? '取消全选' : '全选',
          ),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${rows.length} 项待复核 · 请确认后再交给系统处理',
              style: const TextStyle(color: Color(0xFF818895)),
            ),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 66,
                        color: Color(0xFFB5C6FF),
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
                        style: TextStyle(color: Color(0xFF818895)),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final id = row['media_id'] as String;
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(14),
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
                            left: 2,
                            top: 2,
                            child: Transform.scale(
                              scale: 0.82,
                              child: Checkbox(
                                value: selected.contains(id),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                fillColor: WidgetStateProperty.resolveWith(
                                  (states) =>
                                      states.contains(WidgetState.selected)
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.black45,
                                ),
                                side: const BorderSide(color: Colors.white),
                                onChanged: (value) => setState(() {
                                  if (value == true) {
                                    selected.add(id);
                                  } else {
                                    selected.remove(id);
                                  }
                                }),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 3,
                            top: 3,
                            child: IconButton.filled(
                              tooltip: '恢复此项',
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black45,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.square(28),
                                maximumSize: const Size.square(28),
                                padding: EdgeInsets.zero,
                              ),
                              icon: const Icon(Icons.restore_rounded, size: 17),
                              onPressed: busy ? null : () => _restore([id]),
                            ),
                          ),
                          if (row['status'] == 'unknown' ||
                              row['status'] == 'missing')
                            Positioned(
                              left: 5,
                              bottom: 5,
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
                                    row['status'] == 'missing' ? '不可访问' : '待核对',
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
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy || selected.isEmpty
                      ? null
                      : () => _restore(selected.toList()),
                  child: Text('恢复 ${selected.length} 项'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC3D55),
                  ),
                  onPressed: busy || selected.isEmpty ? null : _process,
                  child: Text(busy ? '等待系统处理…' : '删除 ${selected.length} 项'),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class QueuePreviewScreen extends StatelessWidget {
  const QueuePreviewScreen(this.media, this.item, {super.key});

  final MediaRepository media;
  final MediaRecord item;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('全屏预览'),
      ),
      body: InteractiveViewer(
        key: const Key('queue-preview-zoom'),
        minScale: 1,
        maxScale: 4,
        boundaryMargin: const EdgeInsets.all(80),
        child: SizedBox.expand(child: MediaView(media, item)),
      ),
    ),
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen(this.app, {super.key});
  final CleanerState app;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: AnimatedBuilder(
      animation: app,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '下滑动作',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '修改后只影响之后的操作，已有标记会保留。',
                    style: TextStyle(color: Color(0xFF818895)),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<DownSwipeAction>(
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
                        ButtonSegment(
                          value: DownSwipeAction.skip,
                          label: Text('跳过'),
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
          const SizedBox(height: 22),
          const Text(
            '权限与帮助',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
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
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: '相册清理',
                    children: [
                      const Text('照片和视频仅在本机读取与显示；整理标记保存在本机。删除必须经过队列复核和系统确认。'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            '本地数据',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('清除本地整理记录'),
              subtitle: const Text('不会删除系统照片'),
              onTap: () async {
                final accepted = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('清除本地记录？'),
                    content: const Text('将清除进度、待定、保留和待删除标记，不会删除系统照片。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
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
