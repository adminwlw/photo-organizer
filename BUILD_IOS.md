# iOS 构建说明

## 当前配置

- App 名称：相册清理
- Bundle ID：`com.sim360.albumcleaner.albumCleaner`
- 版本：`0.1.25+26`
- 最低系统：iOS 15.0
- 照片权限说明已经写入 `ios/Runner/Info.plist`
- 当前 App 图标仍为 Flutter 默认图标；正式上架前需要替换 `ios/Runner/Assets.xcassets/AppIcon.appiconset`。

## 免费生成无签名 IPA

项目内的 `.github/workflows/build-ios-unsigned.yml` 会在 GitHub Actions 的 macOS 运行器中执行代码分析、测试和 Release 构建，然后上传 `album-cleaner-ios-unsigned` 构建产物。

1. 将本项目上传到 GitHub 私有仓库的 `main` 分支。
2. 打开仓库的 Actions → Build unsigned iOS IPA。
3. 首次推送会自动构建；以后也可以点击 Run workflow 手动构建。
4. 构建成功后，在该次运行页面底部下载 `album-cleaner-ios-unsigned`，解压得到 `album-cleaner-unsigned.ipa`。

产物是无签名 IPA，仅作为编译交付件，不能直接安装或提交 App Store。

## 在 Mac 上生成 IPA

1. 安装 Xcode 和 Flutter 3.47.7 stable。
2. 在项目目录执行 `flutter pub get`。
3. 用 Xcode 打开 `ios/Runner.xcworkspace`。
4. 选择 Runner → Signing & Capabilities，设置自己的 Apple Developer Team。
5. 确认 Bundle ID 已在 Apple Developer 后台注册；如已占用，请同时修改 Xcode 中的 Bundle ID。
6. 回到项目目录执行：

   ```bash
   chmod +x build_ios.sh
   ./build_ios.sh
   ```

7. 成功后，IPA 位于 `build/ios/ipa/`。

## 真机验收

- 首次启动的照片权限和“有限访问”流程。
- 视频、截屏、实况、自拍、人像、空间照片、空间视频只在系统真实返回时出现。
- 删除队列触发 iOS 系统确认，取消后媒体仍保留。
- 双指缩放、左右浏览方向和删除后的下一张顺序。
