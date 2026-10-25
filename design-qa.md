# 相册清理 App：沉浸式整理页设计核对

## 对照信息

- 视觉来源：`ui-preview/review-reference.png`，用户提供的旧整理页截图，489 × 1059 像素。
- 实现截图：`ui-preview/review-fullscreen.png`，Android 34 模拟器，1080 × 2340 像素，约 393 × 852 dp，设备像素比约 2.75。
- 并排对照：`ui-preview/review-comparison.png`，2161 × 2340 像素。对照时将来源图等比例缩放至 1081 × 2340，未裁剪；实现图保持原始像素。
- 交互证据：`ui-preview/review-swipe-up-result.png`、`review-swipe-down-result.png`、`review-horizontal-test.png`、`review-landscape.png`。
- 状态：52 项模拟器媒体；来源图和实现图使用不同测试照片及索引，因此只对照整理页结构、层级、控件和手势反馈。

## Findings

- 没有剩余 P0、P1 或 P2 问题。
- 字体与层级：进度采用 15sp 粗体白字；手势结果采用 20sp 粗体白字，横竖屏照片上均清晰。系统中文字体没有截断或异常换行。
- 间距与布局：照片区域从顶部状态栏延伸到底部导航栏上方；来源图里的标题栏、照片信息、操作提示、左右按钮和两个底部操作按钮均已移除。返回、进度、队列和撤销为独立悬浮控件，没有形成占据页面高度的菜单栏。
- 颜色与视觉样式：悬浮控件使用 24dp 圆角、半透明底色、18px 背景模糊、浅色描边和柔和阴影。删除结果使用红色，保留结果使用绿色，语义明确且与照片内容保持足够对比。
- 图片质量：设备原始照片通过 `BoxFit.contain` 完整展示；竖屏照片利用整屏高度，横屏照片保持比例并使用黑色留白，没有裁切、拉伸或替换素材。
- 文案：整理页只保留当前项进度和动作结果。上滑显示“已加入待删除”；下滑按用户设置显示“已保留”“已标为待定”或“已跳过”。
- 交互与可访问性：上、下、左、右手势在模拟器实测通过；照片跟随手指位移并在提交时滑出屏幕，动作结果保留 360ms；操作阈值分别为竖向 86dp、横向 72dp。悬浮按钮保留语义标签，撤销只在存在可撤销动作时显示。

## Full-view comparison evidence

`review-comparison.png` 显示旧版页面的大面积白色菜单和底部操作区已被全屏照片取代。实现仍保留返回、进度和待删除队列入口，但改为照片上方的圆角毛玻璃浮层，符合本轮“不要上部菜单”和“照片全屏展示”的目标。

## Focused region comparison evidence

- 顶部控件：`review-fullscreen.png` 可见返回、进度、队列三项均为独立圆角毛玻璃控件，且状态栏背景透明。
- 上下滑反馈：`review-swipe-up-result.png` 和 `review-swipe-down-result.png` 分别显示红色删除结果及绿色保留结果。
- 横竖屏适配：`review-fullscreen.png` 与 `review-landscape.png` 分别验证竖屏照片和横屏照片保持完整比例。

## Comparison history

- Pass 1：来源图存在顶部 AppBar、照片外框、元数据、提示文案、左右翻页按钮和底部动作按钮；按用户本轮要求改为全屏照片与悬浮毛玻璃控件，并加入跟手位移、滑出动画和结果标签。
- Pass 2：在 1080 × 2340 模拟器复核完整整理页、上滑、下滑、横向切换和横屏照片。未发现需要继续修复的 P0、P1 或 P2 差异。

## Runtime verification

- `flutter analyze`：通过，无问题。
- `flutter test`：通过，1 项数据层测试通过。
- Android debug APK：构建并覆盖安装成功。
- 模拟器交互：全屏竖图、完整横图、上滑待删除、下滑保留、左右切换、撤销入口均已检查。
- 运行日志：检查最近 700 行 logcat，没有 Flutter 异常、崩溃或布局溢出。

## Follow-up polish

- P3：真实照片内容可能使毛玻璃控件呈现不同色调；当前白色描边和阴影可保持边界可辨，后续可在实体机上微调模糊强度。

## 三栏信息架构验收

- 底部导航：`ui-preview/three-tabs-home.png`、`three-tabs-albums.png`、`three-tabs-more.png` 验证“首页 / 相册 / 更多”三项导航、当前项高亮和安全区均正常。
- 首页：首次显示“开始整理”；产生整理记录后显示“继续上次整理”、上次位置和日期，证据为 `ui-preview/home-continue.png`。
- 相册分类：显示 PhotoKit / MediaStore 实际返回的系统相册；没有返回的智能分类不造假展示。空相册名统一显示“未命名相册”，证据为 `ui-preview/final-albums.png`。
- 年月视图：`ui-preview/three-tabs-year-month.png` 验证年份位于左侧、月份卡片位于右侧，月份卡显示数量和封面。
- 系统相册：`ui-preview/system-album.png` 与 `system-album-review.png` 验证相册可加载完整媒体网格并进入沉浸式整理页。
- 更多：相册占用空间按照片和视频拆分，媒体类型数量分别展示；`ui-preview/three-tabs-more.png` 中 52 项测试媒体统计为 2.6 MB，无溢出。
- Android 34 模拟器覆盖安装最终 APK 后再次复核三栏页面；最近运行日志没有 Flutter 异常、崩溃或布局溢出。

## 空间与查看手势验收

- `ui-preview/more-storage-compact.png`：照片、视频、截图、实况照片在“相册空间”卡片内压缩为两行；移除图标、数量和说明文案，只显示对应色点与占用容量。进度条使用相同颜色按四个互斥类别的实际容量显示比例。
- `ui-preview/home-no-titlebar.png`、`albums-no-titlebar.png`：首页、相册、更多三个主页面均移除顶部标题栏，底部导航仍明确标识当前位置，并保留下拉刷新。
- `ui-preview/direction-right-before-delete.png`、`direction-right-after-delete-stable.png`：从第 49 项向右滑到第 48 项，删除后继续到第 47 项。
- `ui-preview/direction-left-before-delete.png`、`direction-left-after-delete.png`：从第 47 项向左滑到第 48 项，删除后继续到第 49 项。
- `ui-preview/review-zoomed.png`、`review-zoom-pan.png`：双击放大及放大后的单指拖动通过；整理页同时支持 1–4 倍双指缩放，缩放状态下拖动不会误触发切换或删除。

## 系统分类整理验收

- `ui-preview/home-category-cleanup.png`：首页标题已改为“分类整理”，分类卡片显示图标、名称和数量；Android 使用媒体库可可靠识别的视频与截屏。
- iOS 分类直接读取 PhotoKit 返回的智能相册，只显示数量大于零的分类：视频、截屏、实况、自拍、人像，以及 iOS 18 的空间照片和空间视频。公开 API 没有返回的相似照片不会显示为空分类。
- `ui-preview/more-live-label.png`：更多页“实况照片”已缩短为“实况”。

final result: passed
