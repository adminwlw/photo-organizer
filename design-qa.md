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
- 文案：整理页只保留当前项进度和动作结果。上滑显示“已加入待删除”；下滑可设为返回相册、标记待定或无动作，不再提供跳过。
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

## 图库浮层、时间分组与相册切换验收（2026-10-25）

### 对照信息

- 视觉来源：`ui-preview/final-albums.png`，上一版相册信息架构与视觉语言，1080 × 2340 像素。
- 实现截图：`ui-preview/library-expanded-fixed.png`、`library-collapsed.png`、`library-month-fixed.png`、`library-albums-fixed.png`，Android 10 实体机，720 × 1600 像素，360 × 800 dp，设备像素比 2；最终 release 复验证据为 `release-v0.1.19-library-expanded.png` 与 `release-v0.1.19-library-collapsed.png`。
- 并排对照：`ui-preview/design-qa-comparison.png`，1440 × 1640 像素；来源图等比例归一到 720 × 1560，实现图保持 720 × 1600，顶部标签占 40 像素。
- 状态：114 项真实媒体；实现图依次覆盖初始“图库 / 相册”、滚动后“图库圆形按钮 + 年 / 月 / 全部”、月份卡片和手机相册列表。

### Findings

- 没有剩余 P0、P1 或 P2 问题。
- 字体与层级：页面标题、媒体数量和卡片信息沿用现有系统中文字体与粗细层级；月份标签修复后保持单行，数量独立置于下一行，没有挤压、截断或异常换行。
- 间距与布局：浮动菜单位于底部安全区上方，媒体网格保留 116dp 底部留白；展开态和收起态都没有挡住持久操作入口。手机相册由旧版横向截断列表改为两列纵向网格，名称与数量对齐稳定。
- 颜色与视觉样式：菜单继续使用深色半透明毛玻璃、白色描边和蓝色选中态，与整理页现有悬浮控件一致；月份卡片使用真实封面和底部黑色渐变保证白字对比。
- 图片质量：图库、月份和相册均读取实体机真实缩略图，没有占位素材、拉伸或自绘替代；视频缩略图右下角显示时长并与播放图标分离。
- 文案：菜单固定为“图库 / 相册”和“年 / 月 / 全部”；首页底部仍保留“首页 / 相册 / 更多”。
- 交互与可访问性：滚动开始即收起；圆形图库按钮可再次展开；月份和相册切换在实体机通过。短距离高速横向甩动从 1 / 5 前进到 2 / 5；控件保留语义标签与足够触控面积。

### Full-view comparison evidence

`ui-preview/design-qa-comparison.png` 将上一版相册页与新内嵌相册状态放在同一画布。新实现保留既有浅灰背景、粗体标题、真实封面、两级文字和圆角语言，同时把用户本轮指定的“图库 / 相册”入口移到内容页底部，不再与首页三栏导航冲突。

### Focused region comparison evidence

- `ui-preview/library-expanded-fixed.png`：圆形图库按钮展开后显示“图库 / 相册”，相册选中态明确。
- `ui-preview/library-collapsed.png`：滚动后左侧收成圆形图库图标，右侧显示“年 / 月 / 全部”，默认“全部”选中。
- `ui-preview/library-month-fixed.png`：月份封面、完整月份单行文字和数量均清晰；底部浮层没有覆盖当前首屏主要内容。
- `ui-preview/library-albums-fixed.png`：真实系统相册以两列网格呈现，名称和数量没有截断。
- `ui-preview/review-short-fast-swipe.png`：实体机短距离高速横向甩动成功切换到下一项。
- 删除透视的中间帧受 Android 10 `screencap` 延迟限制未形成可靠静态截图；实体机动作提交通过，矩阵透视、顶部收窄与目标垃圾桶高亮由组件测试覆盖。

### Comparison history

- Pass 1：`ui-preview/library-month.png` 中月份与数量同处一行，`2026年9月` 被挤成不均匀换行，判定为 P2。
- 修复：月份与数量改为左下纵向排布，月份限制单行；新增组件测试约束月份文本高度。
- Pass 2：重新构建并覆盖安装实体机，`ui-preview/library-month-fixed.png` 中 `2026年10月`、`2026年9月` 等均完整单行显示，原 P2 已关闭。

### Runtime verification

- `flutter analyze`：通过，无问题。
- `flutter test`：38 项全部通过。
- Android release APK：在 MED AL00（Android 10、armeabi-v7a）覆盖安装；设备回报 `versionName=0.1.19`、`versionCode=20`，关键交互与最终 release 截图复核通过。
- 本轮未构建 iOS；Windows 环境不能执行 Xcode/iOS 编译。

### Follow-up polish

- P3：不同真实照片会改变毛玻璃底色；当前描边、阴影和选中底板可保持按钮边界，不阻塞交付。

final result: passed

## 双端分类、安全区与待删除预览验收（v0.1.26+27）

- Android 实体机首页：`ui-preview/release-v0.1.26-home.png`。分类整理页已将“全部照片与视频”提升为 84dp 独立主入口，并展示视频、截屏、自拍、实况照片和相似照片；底部“更多”已改为“我的”。
- Android 待删除队列：`ui-preview/release-v0.1.26-queue.png`。单项及批量恢复统一使用“从废纸篓恢复”图标。
- Android 待删除预览：`ui-preview/release-v0.1.26-queue-preview.png`、`release-v0.1.26-queue-returned.png`。适配屏幕时锁定图片位置，放大后才允许平移；返回按钮位于安全区内，下滑 300px 成功返回队列。
- 首尾提示：`ui-preview/release-v0.1.26-first-notice.png`。居中毛玻璃提示无文字下划线或黄线。
- iOS 分类不再从本地文件特征推断：分类入口直接使用 PhotoKit 返回的智能相册名称和成员，覆盖全景、视频、收藏、延时、最近添加、连拍、慢动作、自拍、截屏、人像、实况、动图、长曝光、RAW、电影效果、空间媒体、ProRes、屏幕录制及 iOS 18 的收据、手写、插图、二维码；隐藏相册、无法上传和与主入口重复的系统图库不展示。
- iOS 顶部浮动栏改用系统 `AppBar.primary` 安全区，整理页和待删除预览继续使用 `SafeArea`，不写死灵动岛高度。
- 底部“全部”选中玻璃从 `0xB8E2E9FF` 调整为 `0x8FE2E9FF`；标准文字按钮、分类按钮、图库切换和底部导航文字统一增加轻投影。
- `flutter analyze`：通过，无问题；`flutter test`：44 项全部通过。
- Android 10 实体机已覆盖安装 `0.1.26+27` release 构建并完成上述页面和手势检查。iOS 运行时视觉仍需带灵动岛的真实设备最终确认。

final result: passed with iOS device check pending

## 撤回箭头恢复图标验收（v0.1.27+28）

- source visual truth：`C:\Users\AdminWLWpc\.codex\generated_images\01a161e3-b631-70f1-bf2b-0d12e63e5763\exec-189d5be4-6c2c-4da5-a3e6-4b4816ea805c.png`，1536×1024；用户选择的第 1 款短尾圆角撤回箭头。
- implementation screenshot：`ui-preview/release-v0.1.27-undo-icon-selected.png`，720×1600；Android 10 实体机、待删除队列单项选中状态。
- normalization：两张图的页面比例与内容数量不同，因此全屏只用于确认页面语境；精确比较聚焦于缩略图灰色圆形恢复入口及底部描边恢复按钮，不按页面栅格做像素级比较。
- focused comparison：实现使用 Material `undo_rounded`，箭头方向、短尾、圆角端点、白色缩略图图标和蓝色底部按钮图标均与所选视觉方向一致，小尺寸下轮廓清楚，无垃圾桶残留。
- required surfaces：字体、字号、间距、圆角、颜色、透明度、照片裁切和“恢复”文案均沿用现有组件，没有因本次图标替换发生漂移。
- interactions：单项恢复、批量恢复和待删除复核恢复均由现有测试覆盖；恢复行为未改变。
- findings：无 P0/P1/P2；没有需要阻塞交付的视觉差异。

final result: passed

---

# v0.1.28 设计验收

## 对照对象

- 设计源图：`C:\Users\AdminWLWpc\.codex\generated_images\01a161e3-b631-70f1-bf2b-0d12e63e5763\exec-9125cb2c-84d4-408c-8e4a-8460d6cc9e5d.png`
- 最终实现截图：`E:\DevTools\album_cleaner_workspace\ui-preview\release-v0.1.28-home-final.png`
- 最终并排对照：`E:\DevTools\album_cleaner_workspace\ui-preview\v0.1.28-home-design-qa-comparison-final.png`
- 队列默认态：`E:\DevTools\album_cleaner_workspace\ui-preview\release-v0.1.28-queue.png`
- 队列拖选态：`E:\DevTools\album_cleaner_workspace\ui-preview\release-v0.1.28-queue-drag.png`
- 设备与状态：华为 MED-AL00，Android 10，应用 `0.1.28+29`，真实相册数据，首页与待删除队列。
- 视口：物理像素 `720 x 1600`；Flutter 逻辑宽度约 `360dp`，设备像素比约 `2.0`。
- 密度归一：源图 `841 x 1870` 等比归一为 `720 x 1600`；实现截图原始尺寸 `720 x 1600`，并排图为 `1440 x 1600`。

## Findings

- 无 P0/P1/P2 遗留问题。
- 字体与层级：标题、正文、数字的字号、字重和灰阶层级与源图一致；动态计数不同来自真机数据，不是文案偏差。
- 间距与布局：大卡片起点、分类网格、圆角、两列间距和区块节奏在修正后与源图一致。
- 颜色与视觉令牌：浅蓝背景、蓝色主操作、灰色辅助文本和描边对比与源图一致。
- 图片质量：卡片使用最近三项真实相册缩略图和真实视频标记；真机最近内容恰为截图，因此主体与概念图不同，但符合“使用真实相册媒体”的产品约束。裁切清晰，无占位图或拉伸。
- 文案与交互：`全部照片与视频`、动态数量、队列恢复/删除文案正确；真机从第一个右上角选择框横拖至第三个后连续选中 3 项，底部更新为 `恢复 3 项` / `删除 3 项`。
- 队列控件：单项撤回位于底部中央，右上角选择框可见且触控区放大；两个底部按钮等高，宽度为 2:3。

## Focused region comparison

- 首页大卡片已单独检查：三图斜切、底部磨砂层、左侧图标/标题/数量、右侧圆形箭头均与方案 2 的结构一致。
- 队列交互单独用默认态和拖选态截图检查；关键细节在全页对照中尺寸较小，因此保留上述两张真机证据。

## Comparison history

1. 初次实现：`ui-preview/release-v0.1.28-home.png`；大卡片高度为 `168dp`，比源图高约 40 物理像素，分类区整体下移并把队列卡片挤出首屏，记为 P2。
2. 修正：将大卡片高度改为 `148dp`，同步更新组件测试。
3. 修正后证据：`ui-preview/release-v0.1.28-home-final.png` 与 `ui-preview/v0.1.28-home-design-qa-comparison-final.png`；大卡片和后续分类网格的纵向位置恢复到源图节奏，无剩余 P0/P1/P2。

## Follow-up polish

- P3：Android 状态栏和底部浮动导航占位与概念图略有差异，导致队列卡片首屏只露出顶部；它可滚动访问，不影响核心流程，本次不继续调整平台安全区。

## Verification

- `flutter test`：45/45 通过。
- `flutter analyze`：无问题。
- Android release：构建成功、APK 签名校验通过、真机覆盖安装成功。
- 真机版本：`versionName=0.1.28`，`versionCode=29`。
- 主交互：启动、首页加载、进入队列、单项撤回布局、连续拖选 3 项、底部批量按钮状态均已检查。

final result: passed

---

# v0.1.29 设计与交互验收

## 真机证据

- 首页：`ui-preview/release-v0.1.29-home.png`，华为 MED-AL00、Android 10、真实相册数据。
- 待删除队列默认态：`ui-preview/release-v0.1.29-queue.png`。
- 待删除队列触边拖选结果：`ui-preview/release-v0.1.29-queue-drag.png`。
- 视口为 `720 x 1600` 物理像素，Flutter 逻辑宽度约 `360dp`。

## Findings

- 首页已显示最终选定 Logo 与暂定名称“相册删除”；Logo 在小尺寸下轮廓清晰，名称没有截断。
- “继续整理”卡片高度缩至 `96dp`，主次信息仍完整可读。
- “全部照片与视频”已移到“分类整理”之前，真机尺寸为 4:3；三张真实媒体封面、数量和入口按钮均正常。
- 标题底色由上方完全透明渐变到下方白色，文字在复杂照片上保持可读。
- 真机从第一项右上角选择框连续拖到网格下边缘，列表自动滚动至末尾并选中全部 33 项；底部同步显示“恢复 33 项 / 删除 33 项”。验证后已取消全选，没有执行删除。
- Android 不伪造 Live Photo 能力；长按播放仅在 iOS 的真实 PhotoKit Live Photo 上启用。Windows 无法完成 iOS 真机播放验收。
- 无 P0/P1/P2 遗留问题。

## Verification

- `flutter test`：48/48 通过。
- `flutter analyze`：无问题。
- Android release：ARM32/ARM64 构建成功，真机覆盖安装成功。
- 真机版本：`versionName=0.1.29`，`versionCode=30`；应用标签为“相册删除”。

final result: passed with iOS Live Photo device check pending
