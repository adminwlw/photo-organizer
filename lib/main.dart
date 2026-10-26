import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import 'media_repository.dart';
import 'store.dart';

const _buttonTextShadows = [
  Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
];

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

class _FloatingGlassAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _FloatingGlassAppBar({required this.title, this.actions});

  final Widget title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) => AppBar(
    primary: true,
    toolbarHeight: 68,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    title: title,
    actions: actions,
    flexibleSpace: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0x70FFFFFF),
                border: Border.all(color: const Color(0x99FFFFFF)),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _MediaGradientAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _MediaGradientAppBar({
    required this.media,
    required this.title,
    required this.subtitle,
    this.coverId,
    this.actions,
  });

  final MediaRepository media;
  final String title;
  final String subtitle;
  final String? coverId;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(88);

  @override
  Widget build(BuildContext context) => AppBar(
    key: const Key('media-gradient-app-bar'),
    primary: true,
    toolbarHeight: 88,
    automaticallyImplyLeading: false,
    backgroundColor: const Color(0xFF2B3037),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
    ),
    leadingWidth: 68,
    leading: Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Center(
        child: Material(
          color: const Color(0x52000000),
          shape: const CircleBorder(side: BorderSide(color: Color(0x66FFFFFF))),
          child: IconButton(
            key: const Key('media-header-back'),
            tooltip: '返回',
            onPressed: () => Navigator.maybePop(context),
            color: Colors.white,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
        ),
      ),
    ),
    titleSpacing: 6,
    title: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            height: 1.08,
            shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
          ),
        ),
      ],
    ),
    actions: actions,
    flexibleSpace: Stack(
      fit: StackFit.expand,
      children: [
        if (coverId != null)
          MediaThumb(
            media,
            coverId!,
            width: 1080,
            height: 360,
            showPlaceholderIcon: false,
            placeholderColor: const Color(0xFF2B3037),
          ),
        const DecoratedBox(
          key: Key('media-header-gradient'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xE6000000), Color(0xAD11151A), Color(0xF22B3037)],
              stops: [0, 0.56, 1],
            ),
          ),
        ),
      ],
    ),
  );
}

class _HeaderSelectButton extends StatelessWidget {
  const _HeaderSelectButton({required this.selecting, required this.onPressed});

  final bool selecting;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: Center(
      child: TextButton(
        key: const Key('media-select-button'),
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white54,
          backgroundColor: const Color(0x52000000),
          side: const BorderSide(color: Color(0x66FFFFFF)),
          minimumSize: const Size(62, 44),
          shape: const StadiumBorder(),
        ),
        child: Text(selecting ? '取消' : '选择'),
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
      color: selected ? const Color(0xFF1557F8) : const Color(0x66000000),
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
    minimum: const EdgeInsets.fromLTRB(16, 0, 16, 4),
    child: Align(
      alignment: Alignment.bottomCenter,
      child: ClipRRect(
        key: const Key('batch-queue-bar'),
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: 58,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0x66000000),
              border: Border.all(color: const Color(0x66FFFFFF)),
              borderRadius: BorderRadius.circular(28),
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('batch-queue-button'),
                onPressed: busy || selectedCount == 0 ? null : onQueue,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1557F8),
                  disabledBackgroundColor: const Color(0x668A8F99),
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
      'keep' || 'returnToAlbum' || 'skip' => DownSwipeAction.returnToAlbum,
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
    title: '相册删除',
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
          textStyle: const TextStyle(shadows: _buttonTextShadows),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(shadows: _buttonTextShadows),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: const TextStyle(shadows: _buttonTextShadows),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          textStyle: const TextStyle(shadows: _buttonTextShadows),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(shadows: _buttonTextShadows),
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
  static const pages = [
    'assets/tutorial/tutorial-01.png',
    'assets/tutorial/tutorial-02.png',
    'assets/tutorial/tutorial-03.png',
    'assets/tutorial/tutorial-04.png',
  ];
  final PageController pager = PageController();
  Timer? playbackTimer;
  int page = 0;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _schedulePlayback();
  }

  void _schedulePlayback() {
    playbackTimer?.cancel();
    if (page == pages.length - 1) return;
    playbackTimer = Timer(const Duration(milliseconds: 2800), () {
      if (!mounted || !pager.hasClients || busy) return;
      pager.nextPage(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _pageLabel(int index) => switch (index) {
    0 => '左右滑动预览照片，左滑下一张，右滑上一张',
    1 => '上滑删除不想保留的照片，并自动进入下一张',
    2 => '下滑动作可以设置为无、待定或返回相册，当前为${widget.downAction.label}',
    _ => '左右预览，上滑删除，下滑动作可以自定义',
  };

  @override
  void dispose() {
    playbackTimer?.cancel();
    pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F8FD),
    appBar: Navigator.canPop(context)
        ? AppBar(
            title: const Text('使用教程'),
            backgroundColor: const Color(0xFFF5F8FD),
          )
        : null,
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              key: const Key('onboarding-pager'),
              controller: pager,
              itemCount: pages.length,
              onPageChanged: (value) {
                setState(() => page = value);
                _schedulePlayback();
              },
              itemBuilder: (context, index) => Semantics(
                label: _pageLabel(index),
                image: true,
                child: Image.asset(
                  pages[index],
                  key: ValueKey('onboarding-page-${index + 1}'),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
            child: Row(
              children: [
                Row(
                  children: List.generate(
                    pages.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: index == page ? 28 : 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 7),
                      decoration: BoxDecoration(
                        color: index == page
                            ? const Color(0xFF175CF5)
                            : const Color(0xFFC8D2DF),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${page + 1} / ${pages.length}',
                  key: const Key('onboarding-page-indicator'),
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (page > 0)
                  IconButton(
                    key: const Key('onboarding-previous'),
                    tooltip: '上一页',
                    onPressed: () => pager.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                    ),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                FilledButton(
                  key: const Key('onboarding-next'),
                  onPressed: busy
                      ? null
                      : () async {
                          if (page < pages.length - 1) {
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
                  child: Text(page == pages.length - 1 ? '开始清理' : '下一页'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
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
  late Future<List<SystemAlbumSummary>> systemAlbums;
  late Future<List<SystemCategorySummary>> systemCategories;
  late Future<List<MediaRecord>> allMediaCover;
  late Future<List<int>> localCategoryCounts;
  late Future<int> similarPhotoCount;
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
    allMediaCover = _loadAllMediaCover();
    localCategoryCounts = _loadLocalCategoryCounts();
    similarPhotoCount = _loadSimilarPhotoCount();
  }

  Future<List<MediaRecord>> _loadAllMediaCover() async => (await Future.wait([
    for (var index = 0; index < 4; index++) app.store.at(Scope.all, index),
  ])).whereType<MediaRecord>().toList();

  Future<List<int>> _loadLocalCategoryCounts() => Future.wait([
    app.store.count(Scope.videos),
    app.store.count(Scope.screenshots),
    app.store.count(Scope.selfies),
    app.store.count(Scope.live),
  ]);

  Future<int> _loadSimilarPhotoCount() async {
    final groups = await app.media.findSimilarPhotos(app.store, (_, _) {});
    return groups.fold<int>(0, (total, group) => total + group.items.length);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) {
      setState(() => allMediaCover = _loadAllMediaCover());
    }
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
      allMediaCover = _loadAllMediaCover();
      localCategoryCounts = _loadLocalCategoryCounts();
      similarPhotoCount = _loadSimilarPhotoCount();
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
    key: ValueKey('section-$title'),
    padding: const EdgeInsets.fromLTRB(2, 22, 2, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF111A35),
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
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

  Widget _brandHeader() => Row(
    key: const Key('home-brand'),
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Image.asset(
          'assets/app-logo.png',
          key: const Key('home-brand-logo'),
          width: 46,
          height: 46,
        ),
      ),
      const SizedBox(width: 11),
      const Expanded(
        child: Text(
          '相册删除',
          style: TextStyle(
            color: Color(0xFF111A35),
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      Material(
        color: const Color(0xD9FFFFFF),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: const Key('home-settings'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => _open(SettingsScreen(app)),
          child: const SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              Icons.settings_outlined,
              color: Color(0xFF1557F8),
              size: 27,
            ),
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
                left: 9,
                top: 9,
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
                                color: Color(0xE6000000),
                                blurRadius: 10,
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
                                  color: Color(0xE6000000),
                                  blurRadius: 10,
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
                right: 9,
                bottom: 9,
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
                              color: Color(0xE6000000),
                              blurRadius: 10,
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

  Widget _heroPhoto(MediaRecord? item, {Key? key}) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white, width: 4),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1A23469A),
          blurRadius: 16,
          offset: Offset(0, 7),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: item == null
          ? const ColoredBox(
              color: Color(0xFFDCEBFF),
              child: Icon(
                Icons.photo_library_outlined,
                color: Color(0xFF78A7FF),
              ),
            )
          : MediaThumb(app.media, item.id, key: key, width: 240, height: 180),
    ),
  );

  Widget _heroIntro() => SizedBox(
    height: 160,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final artWidth = (constraints.maxWidth * 0.46)
            .clamp(132.0, 172.0)
            .toDouble();
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 26,
              width: constraints.maxWidth - artWidth + 8,
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
              right: 0,
              top: 0,
              width: artWidth,
              height: 152,
              child: FutureBuilder<List<MediaRecord>>(
                future: allMediaCover,
                builder: (context, snapshot) {
                  final items = snapshot.data ?? const <MediaRecord>[];
                  MediaRecord? itemAt(int index) =>
                      index < items.length ? items[index] : null;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        right: 8,
                        top: 4,
                        width: 112,
                        height: 82,
                        child: Transform.rotate(
                          angle: 0.08,
                          child: _heroPhoto(
                            itemAt(0),
                            key: const Key('home-hero-photo-0'),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 38,
                        top: 60,
                        width: 108,
                        height: 80,
                        child: Transform.rotate(
                          angle: -0.08,
                          child: _heroPhoto(
                            itemAt(1),
                            key: const Key('home-hero-photo-1'),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -1,
                        top: 77,
                        width: 103,
                        height: 75,
                        child: Transform.rotate(
                          angle: 0.1,
                          child: _heroPhoto(
                            itemAt(2),
                            key: const Key('home-hero-photo-2'),
                          ),
                        ),
                      ),
                    ],
                  );
                },
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
        return Material(
          color: Colors.transparent,
          child: InkWell(
            key: const Key('review-hero'),
            borderRadius: BorderRadius.circular(22),
            onTap: enabled
                ? () => _open(ScopeScreen(app, Scope.all, startReview: true))
                : null,
            child: Ink(
              height: 76,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF36A7F4),
                    Color(0xFF3E77F7),
                    Color(0xFF7565F2),
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x294663EF),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
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
                            backgroundColor: const Color(0x55FFFFFF),
                            color: Colors.white,
                          ),
                        ),
                        Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Colors.white,
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
                            color: Colors.white,
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
                            color: Color(0xE6FFFFFF),
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
                      color: enabled ? Colors.white : const Color(0x99FFFFFF),
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
    SystemCategoryKind.portraits => Icons.portrait_outlined,
    SystemCategoryKind.animated => Icons.animation_rounded,
    SystemCategoryKind.longExposures => Icons.shutter_speed_rounded,
    SystemCategoryKind.raw => Icons.raw_on_outlined,
    SystemCategoryKind.cinematic => Icons.movie_filter_outlined,
    SystemCategoryKind.spatial => Icons.view_in_ar_outlined,
    SystemCategoryKind.proRes => Icons.high_quality_outlined,
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
    Color accent = const Color(0xFF1557F8),
    Color surface = const Color(0xFFF3F6FF),
  }) => SizedBox(
    height: 72,
    child: InkWell(
      key: key,
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent, size: 21),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF111A35),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    countText ?? (count == null ? '读取中' : '$count 项'),
                    style: const TextStyle(
                      color: Color(0xFF6E7892),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.66),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: const Color(0xFF193B8F),
                size: 20,
              ),
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

  Widget _allMediaMosaic(List<MediaRecord> items) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemBuilder: (context, index) => index < items.length
          ? _allMediaCoverCell(items[index], index)
          : const ColoredBox(
              color: Color(0xFFEAF2FF),
              child: Icon(
                Icons.image_outlined,
                color: Color(0xFFAAC3F8),
                size: 24,
              ),
            ),
    );
  }

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
                        const SizedBox(height: 8),
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

  Widget _similarCategoryTile() => FutureBuilder<int>(
    future: similarPhotoCount,
    builder: (context, snapshot) => _compactCategoryTile(
      key: const ValueKey('category-similar'),
      icon: Icons.auto_awesome_mosaic_outlined,
      label: '相似照片',
      count: snapshot.data,
      accent: const Color(0xFF119C9A),
      surface: const Color(0xFFF0FBF8),
      onTap: () => _open(SimilarPhotosScreen(app)),
    ),
  );

  Widget _compactCategoryList(List<Widget> children) {
    if (children.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[];
    var index = 0;
    if (children.length > 1) {
      rows.add(
        Row(
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 10),
            Expanded(child: children[1]),
          ],
        ),
      );
      index = 2;
    }
    for (; index < children.length; index++) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      rows.add(children[index]);
    }
    return Column(
      key: const Key('category-grid'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _categoryGrid() {
    if (!Platform.isIOS) {
      const categories = [
        (
          Scope.videos,
          Icons.videocam_outlined,
          Color(0xFF078CA6),
          Color(0xFFF0FBFD),
        ),
        (
          Scope.screenshots,
          Icons.screenshot_outlined,
          Color(0xFF6C4BEF),
          Color(0xFFF7F4FF),
        ),
        (
          Scope.selfies,
          Icons.face_outlined,
          Color(0xFFE8863A),
          Color(0xFFFFF7EF),
        ),
        (
          Scope.live,
          Icons.motion_photos_on_outlined,
          Color(0xFF3978DD),
          Color(0xFFF1F6FF),
        ),
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
                  surface: categories[index].$4,
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
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          excludeFromSemantics: true,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          children: [
            _brandHeader(),
            const SizedBox(height: 12),
            _heroIntro(),
            const SizedBox(height: 4),
            _reviewHero(),
          ],
        ),
      ),
    ],
  );

  Widget _home() => ListView(
    key: const Key('home-scroll'),
    padding: const EdgeInsets.only(bottom: 112),
    children: [
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
            _sectionTitle('照片总览'),
            _allMediaCategoryTile(),
            _sectionTitle('分类整理'),
            _categoryGrid(),
            if (Platform.isAndroid)
              const Padding(
                padding: EdgeInsets.only(top: 18),
                child: Text(
                  '自拍和动态照片在 Android 上没有统一的可靠标记，可在“全部”中查看。',
                  style: TextStyle(color: Color(0xFF818895), fontSize: 12),
                ),
              ),
          ],
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
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _albumGridColumnCount(
              MediaQuery.sizeOf(context).width,
            ),
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
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 112),
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

  Widget _albums() => _albumCategories();

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
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 112),
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
      child: [_home(), _albums(), _more()][tab],
    ),
  );

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: const Color(0xFFF6FAFF),
      systemStatusBarContrastEnforced: false,
    ),
    child: Scaffold(
      backgroundColor: const Color(0xFFF6FAFF),
      extendBody: true,
      body: SafeArea(
        bottom: false,
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
            : _tabBody(),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: ClipRRect(
            key: const Key('home-glass-nav'),
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x70FFFFFF),
                  border: Border.all(color: const Color(0x99FFFFFF)),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: NavigationBar(
                  height: 70,
                  selectedIndex: tab,
                  onDestinationSelected: (index) {
                    setState(() => tab = index);
                    if (index == 2) _calculateStorage();
                  },
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  indicatorColor: const Color(0xB8E2E9FF),
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
                      icon: Icon(Icons.person_outline_rounded),
                      selectedIcon: Icon(Icons.person_rounded),
                      label: '我的',
                    ),
                  ],
                ),
              ),
            ),
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

  void _pointerDown(PointerDownEvent event) {
    if (!widget.enabled || widget.busy) return;
    final index = _indexAt(event.position);
    if (index == null) return;
    pointer = event.pointer;
    startIndex = index;
    startPosition = event.position;
    selectionBase = {
      for (var item = 0; item < widget.itemCount; item++)
        if (widget.isSelected(item)) item,
    };
    dragActive = false;
    dragPosition = null;
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
    _resetDrag();
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
    behavior: HitTestBehavior.translucent,
    onPointerDown: widget.enabled ? _pointerDown : null,
    onPointerMove: widget.enabled ? _pointerMove : null,
    onPointerUp: widget.enabled ? _pointerEnd : null,
    onPointerCancel: widget.enabled ? _pointerEnd : null,
    child: GridView.builder(
      key: widget.gridKey,
      controller: widget.controller,
      physics: widget.enabled ? const NeverScrollableScrollPhysics() : null,
      padding: widget.padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.crossAxisCount,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: widget.itemCount,
      itemBuilder: widget.itemBuilder,
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
  String? coverId;
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
    coverId = widget.album.coverId;
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
        coverId = visible.isEmpty ? null : visible.first.id;
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
        coverId = records?.isEmpty == false ? records!.first.id : null;
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
    appBar: _MediaGradientAppBar(
      media: widget.app.media,
      title: title,
      subtitle: selecting
          ? '已选择 ${selected.length} 项'
          : '${records?.length ?? total} 个项目',
      coverId: coverId,
      actions: [
        if (!selecting)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Center(
              child: IconButton(
                key: const Key('album-start-review'),
                tooltip: '开始整理',
                onPressed: records?.isNotEmpty == true && !queueing
                    ? _review
                    : null,
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white54,
                  backgroundColor: const Color(0x52000000),
                  side: const BorderSide(color: Color(0x66FFFFFF)),
                ),
                icon: const Icon(Icons.swipe_rounded),
              ),
            ),
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
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 82),
            crossAxisCount: _photoGridColumnCount(
              MediaQuery.sizeOf(context).width,
            ),
            itemCount: records!.length,
            enabled: selecting,
            busy: queueing,
            isSelected: (index) => selected.containsKey(records![index].id),
            onSelectionChanged: _updateSelectedIndexes,
            itemBuilder: (context, index) {
              final item = records![index];
              final isSelected = selected.containsKey(item.id);
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
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
                                    color: const Color(0xFF1557F8),
                                    width: 3,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
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

class _SimilarPhotosScreenState extends State<SimilarPhotosScreen> {
  List<SimilarPhotoGroup>? groups;
  int processed = 0;
  int total = 0;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      groups = null;
      failed = false;
      processed = 0;
      total = 0;
    });
    try {
      final result = await widget.app.media.findSimilarPhotos(
        widget.app.store,
        (value, maximum) {
          if (!mounted) return;
          setState(() {
            processed = value;
            total = maximum;
          });
        },
      );
      if (mounted) setState(() => groups = result);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
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
          style: TextStyle(color: Color(0xFF818895), fontSize: 12),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const _FloatingGlassAppBar(title: Text('相似照片')),
    body: failed
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('相似照片分析失败'),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          )
        : groups == null
        ? _loading()
        : groups!.isEmpty
        ? const Center(child: Text('暂未发现相似照片'))
        : ListView.separated(
            key: const Key('similar-groups'),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            itemCount: groups!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 22),
            itemBuilder: (context, groupIndex) {
              final group = groups![groupIndex];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '第 ${groupIndex + 1} 组 · ${group.items.length} 张',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 116,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: group.items.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final item = group.items[index];
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            key: ValueKey('similar-${item.id}'),
                            onTap: () => _review(group, index),
                            child: SizedBox.square(
                              dimension: 116,
                              child: MediaThumb(widget.app.media, item.id),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
  );
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
  });
  final CleanerState app;
  final Scope scope;
  final bool startReview;

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
  String? coverId;

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
    final cover = total == 0
        ? null
        : await widget.app.store.at(widget.scope, 0, pendingOnly: pendingOnly);
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
      coverId = cover?.id;
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
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 116),
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
      borderRadius: BorderRadius.circular(10),
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
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF1557F8),
                          width: 3,
                        ),
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
                      borderRadius: BorderRadius.circular(10),
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
    final padding = EdgeInsets.fromLTRB(
      4,
      6,
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
    if (showingAlbums) return _LibraryAlbumsView(widget.app);
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
                alignment: Alignment.bottomLeft,
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
                          color: Color(0xFF1557F8),
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
                                selectedColor: mode == _LibraryTimeMode.all
                                    ? const Color(0x8FE2E9FF)
                                    : const Color(0xB8E2E9FF),
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
    appBar: _MediaGradientAppBar(
      media: widget.app.media,
      title: widget.scope.label,
      subtitle: selecting ? '已选择 ${selected.length} 项' : '$count 个项目',
      coverId: coverId,
      actions: [
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
        Column(
          children: [
            if (!selecting &&
                !showingAlbums &&
                libraryTimeMode == _LibraryTimeMode.all &&
                widget.app.downAction == DownSwipeAction.pending)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const Key('pending-filter-entry'),
                    onPressed: () {
                      setState(() {
                        pendingOnly = !pendingOnly;
                        _leaveSelection();
                      });
                      _refresh();
                    },
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
            Expanded(child: _content()),
          ],
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
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: SizedBox(
        height: 56,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x70FFFFFF),
            border: Border.all(color: const Color(0x99FFFFFF)),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    ),
  );
}

class _LibraryControlItem extends StatelessWidget {
  const _LibraryControlItem({
    super.key,
    this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedColor = const Color(0xB8E2E9FF),
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
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 21,
                color: selected
                    ? const Color(0xFF1557F8)
                    : const Color(0xFF444A55),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF10131A)
                    : const Color(0xFF5F6672),
                fontSize: 15,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                shadows: _buttonTextShadows,
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
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
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
                      fontWeight: FontWeight.w800,
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
  const _LibraryAlbumsView(this.app);

  final CleanerState app;

  @override
  State<_LibraryAlbumsView> createState() => _LibraryAlbumsViewState();
}

class _LibraryAlbumsViewState extends State<_LibraryAlbumsView> {
  late final Future<List<SystemAlbumSummary>> albums;

  @override
  void initState() {
    super.initState();
    albums = widget.app.media.systemAlbums();
  }

  Widget _section(String title, List<SystemAlbumSummary> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 22, 0, 12),
          child: Text(
            title,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _albumGridColumnCount(
              MediaQuery.sizeOf(context).width,
            ),
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
            childAspectRatio: 0.88,
          ),
          itemBuilder: (context, index) {
            final album = items[index];
            return InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SystemAlbumScreen(widget.app, album),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
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
                      color: Color(0xFF818895),
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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 116),
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
  static const reviewBackground = Color(0xFFF3F4F6);
  static const _horizontalFlingVelocity = 700.0;
  static const _verticalFlingVelocity = 900.0;
  static const _horizontalFlingDistance = 24.0;
  static const _verticalFlingDistance = 32.0;
  static const _verticalActionDistance = 76.0;

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
  List<MediaRecord>? sourceItems;
  late final List<MediaRecord>? sourceOrder;
  late final AnimationController motion;
  late Animation<Offset> motionAnimation;
  late Animation<double> scaleAnimation;
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
                    color: const Color(0x70FFFFFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0x99FFFFFF)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x26000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
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
                        color: Color(0xFF10131A),
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
    return sourceItems == null
        ? widget.app.store.at(
            widget.scope,
            target,
            pendingOnly: widget.pendingOnly,
            unreviewedOnly: !widget.pendingOnly,
          )
        : sourceItems![target];
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
          navigator.pop(current?.id);
        } else {
          setState(() => busy = false);
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
      if (sourceOrder != null) await _refreshSource();
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
                  videoProgressBottom: 18,
                ),
              ),
            Transform.translate(
              key: const Key('media-drag-translation'),
              offset: dragOffset,
              child: Transform.scale(
                key: const Key('action-media-scale'),
                scale: actionScale,
                child: Transform.translate(
                  offset: zoomOffset,
                  child: Transform.scale(
                    scale: zoom,
                    child: MediaView(
                      widget.app.media,
                      item,
                      key: ValueKey(item.id),
                      previewBytes: currentPreview,
                      videoProgressBottom: 18,
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
                      color: const Color(0x52FFFFFF),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: _glass(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 8,
                      ),
                      color: const Color(0x52FFFFFF),
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
                                diameter: 40,
                                iconSize: 20,
                                color: Color.lerp(
                                  const Color(0x52FFFFFF),
                                  const Color(0xF2DC3D55),
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
                                : const Color(0x52FFFFFF),
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
    Color color = const Color(0x52FFFFFF),
  }) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26000000),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.62)),
          ),
          child: child,
        ),
      ),
    ),
  );

  Widget _glassIcon({
    Key? key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    double diameter = 48,
    double iconSize = 22,
    Color color = const Color(0x52FFFFFF),
  }) => _glass(
    padding: EdgeInsets.zero,
    color: color,
    child: IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      color: Colors.white,
      disabledColor: Colors.white60,
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
    this.videoProgressBottom = 10,
  });
  final MediaRepository media;
  final MediaRecord item;
  final Uint8List? previewBytes;
  final bool autoplay;
  final double videoProgressBottom;

  @override
  State<MediaView> createState() => _MediaViewState();
}

class _MediaViewState extends State<MediaView> {
  VideoPlayerController? player;
  bool loading = false;
  bool livePhotoPressed = false;
  bool livePhotoPlaying = false;

  bool get canPlayLivePhoto =>
      widget.item.live && widget.media.supportsLivePhotoPlayback;

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
    final showVideo =
        player?.value.isInitialized == true &&
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
                      if (widget.item.live)
                        const Positioned(
                          key: Key('live-photo-badge'),
                          left: 12,
                          top: 12,
                          child: _LivePhotoBadge(showLabel: true),
                        ),
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
                          key: const Key('video-progress'),
                          left: 18,
                          right: 18,
                          bottom: widget.videoProgressBottom,
                          child: DefaultTextStyle(
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                Shadow(color: Colors.black87, blurRadius: 6),
                              ],
                            ),
                            child: _videoProgress(),
                          ),
                        ),
                    ],
                  ),
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
        local.dy + (queueScroll.hasClients ? queueScroll.offset : 0);
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
        builder: (_) => QueuePreviewScreen(
          widget.app.media,
          media,
          onKeep: () => _restore([id]),
          onDelete: () => _process([id]),
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
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('清理完成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '本次清理 ${removedIds.length} 项',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '预计涉及空间 ${_formatResultBytes(removedBytes)}',
                style: const TextStyle(
                  color: Color(0xFF1557F8),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
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
                style: const TextStyle(color: Color(0xFF687086)),
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
    appBar: _FloatingGlassAppBar(
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
                  key: queueGridKey,
                  controller: queueScroll,
                  physics: selectionPointer == null
                      ? null
                      : const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
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
                                    fillColor: WidgetStateProperty.resolveWith(
                                      (states) =>
                                          states.contains(WidgetState.selected)
                                          ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                          : Colors.black45,
                                    ),
                                    side: const BorderSide(color: Colors.white),
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
                flex: 2,
                child: SizedBox(
                  key: const Key('queue-restore-selected'),
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: busy || selected.isEmpty
                        ? null
                        : () => _restore(selected.toList()),
                    icon: const Icon(Icons.undo_rounded),
                    label: Text('保留 ${selected.length} 项'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: SizedBox(
                  key: const Key('queue-delete-selected'),
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFDC3D55),
                    ),
                    onPressed: busy || selected.isEmpty
                        ? null
                        : () => _process(selected),
                    child: Text(busy ? '等待系统处理…' : '删除 ${selected.length} 项'),
                  ),
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
  });

  final MediaRepository media;
  final MediaRecord item;
  final Future<bool> Function() onKeep;
  final Future<bool> Function() onDelete;

  @override
  State<QueuePreviewScreen> createState() => _QueuePreviewScreenState();
}

class _QueuePreviewScreenState extends State<QueuePreviewScreen> {
  final transformation = TransformationController();
  final pointers = <int>{};
  Offset swipeOffset = Offset.zero;
  bool zoomed = false;
  bool busy = false;

  @override
  void dispose() {
    transformation.dispose();
    super.dispose();
  }

  void _updateZoom() {
    final next = transformation.value.getMaxScaleOnAxis() > 1.01;
    if (next != zoomed) setState(() => zoomed = next);
  }

  void _finishSwipe() {
    if (!zoomed &&
        swipeOffset.dy > 80 &&
        swipeOffset.dy > swipeOffset.dx.abs() * 1.25) {
      Navigator.maybePop(context);
    }
    swipeOffset = Offset.zero;
  }

  Future<void> _act(Future<bool> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final changed = await action();
      if (changed && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _glass({required Widget child, EdgeInsets? padding}) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x52000000),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x66FFFFFF)),
        ),
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.black,
    ),
    child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Listener(
            key: const Key('queue-preview-surface'),
            onPointerDown: (event) {
              pointers.add(event.pointer);
              if (pointers.length == 1) swipeOffset = Offset.zero;
            },
            onPointerMove: (event) {
              if (pointers.length == 1 && !zoomed) {
                swipeOffset += event.delta;
              }
            },
            onPointerUp: (event) {
              final wasSinglePointer = pointers.length == 1;
              pointers.remove(event.pointer);
              if (wasSinglePointer) _finishSwipe();
            },
            onPointerCancel: (event) {
              pointers.remove(event.pointer);
              swipeOffset = Offset.zero;
            },
            child: InteractiveViewer(
              key: const Key('queue-preview-zoom'),
              transformationController: transformation,
              minScale: 1,
              maxScale: 4,
              panEnabled: zoomed,
              boundaryMargin: EdgeInsets.zero,
              onInteractionUpdate: (_) => _updateZoom(),
              onInteractionEnd: (_) {
                if (transformation.value.getMaxScaleOnAxis() <= 1.01) {
                  transformation.value = Matrix4.identity();
                }
                _updateZoom();
              },
              child: SizedBox.expand(
                child: MediaView(widget.media, widget.item),
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: _glass(
                    child: IconButton(
                      key: const Key('queue-preview-back'),
                      tooltip: '返回待删除列表',
                      onPressed: () => Navigator.maybePop(context),
                      color: Colors.white,
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
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
                        _glass(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white,
                              ),
                              SizedBox(width: 5),
                              Text(
                                '下滑返回待删除列表',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  shadows: _buttonTextShadows,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 52,
                                child: OutlinedButton.icon(
                                  key: const Key('queue-preview-keep'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    backgroundColor: Colors.black54,
                                    side: const BorderSide(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  onPressed: busy
                                      ? null
                                      : () => _act(widget.onKeep),
                                  icon: const Icon(Icons.undo_rounded),
                                  label: const Text('保留此项'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 52,
                                child: FilledButton.icon(
                                  key: const Key('queue-preview-delete'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFDC3D55),
                                  ),
                                  onPressed: busy
                                      ? null
                                      : () => _act(widget.onDelete),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('删除此项'),
                                ),
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
    appBar: const _FloatingGlassAppBar(title: Text('设置')),
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
                    applicationName: '相册删除',
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
