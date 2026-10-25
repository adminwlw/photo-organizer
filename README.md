# 相册清理 MVP

Flutter 相册整理应用，支持 Android 10+ 与 iOS 15+。当前源码包含本机照片/视频浏览、月份与可识别类别、逐张手势整理、可自定义下滑动作、撤销、SQLite 进度、待删除队列和系统删除确认。媒体不上传服务器。

## 本地运行

1. 安装 Flutter 3.47+、Android SDK（API 29+）和一台 Android 10+ 设备或虚拟设备。iOS 构建需要 macOS、Xcode 与 CocoaPods。
2. 在本目录运行 `flutter pub get`、`flutter analyze`、`flutter test`。
3. 运行 `flutter devices` 选择设备，再运行 `flutter run -d <设备 ID>`。
4. 只用专门创建的测试媒体验证删除。上滑只是标记；在待删除队列再次复核后才会请求系统移入回收站或最近删除。

Windows 本机准备的工具：`E:\DevTools\flutter`、`E:\DevTools\AndroidSdk`、`E:\DevTools\album_cleaner_workspace`（指向本目录的目录联接）。本机的 Flutter 分析服务对中文工作路径报错，Gradle 构建还需要与项目同盘的 Pub 缓存和短临时路径。可在 PowerShell 中这样运行：

```powershell
Set-Location 'E:\DevTools\album_cleaner_workspace'
$env:PUB_CACHE = 'E:\DevTools\PubCache'
$env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=E:\DevTools\jdk-socket-tmp'
& 'E:\DevTools\flutter\bin\flutter.bat' pub get
& 'E:\DevTools\flutter\bin\flutter.bat' analyze
& 'E:\DevTools\flutter\bin\flutter.bat' test
& 'E:\DevTools\flutter\bin\flutter.bat' build apk --debug
```

APK 输出为 `build\app\outputs\flutter-apk\app-debug.apk`。虚拟设备名为 `AlbumCleaner_API34`，可用 Android Studio 启动，或运行 `E:\DevTools\AndroidSdk\emulator\emulator.exe -avd AlbumCleaner_API34`。这个工作环境的 JDK 已通过 `flutter config --jdk-dir` 指向 Eclipse Temurin 21。

## Android 兼容与发布包

- Android 最低兼容版本固定为 Android 10（API 29）。后续开发、依赖升级和打包都必须保留该下限；如确需提高，先确认设备范围并取得明确同意。
- 直接分发一个 APK 时，仅包含手机和平板需要的 ARM32、ARM64 架构，避免把模拟器专用的 x86_64 引擎装进发布包：

```powershell
& 'E:\DevTools\flutter\bin\flutter.bat' build apk --release --target-platform android-arm,android-arm64
```

- 需要更小的安装包时，按 CPU 架构拆包：

```powershell
& 'E:\DevTools\flutter\bin\flutter.bat' build apk --release --split-per-abi
```

  真机只分发 `armeabi-v7a` 或 `arm64-v8a` 对应的 APK；`x86_64` 仅供模拟器使用。上架应用商店时优先构建 AAB，由商店为设备下发单一架构。

## 当前边界

- Android 截图按目录/文件名识别；自拍和厂商动态照片没有可靠统一标记。iOS 截图、自拍、实况分类通过 PhotoKit 数据识别。
- 广告和未来的终身去广告购买尚未接入；需要先确定广告平台、账号及隐私同意方案。当前整理和删除功能免费。
- Windows 可以构建 Android APK；iOS 包与 PhotoKit 真机行为需在 Mac 上验证。
