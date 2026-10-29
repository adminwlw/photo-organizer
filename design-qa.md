# 参考图首页 Design QA

## 当前对比目标（2026-10-27）

- Source visual truth: `C:\Users\ADMINW~1\AppData\Local\Temp\codex-clipboard-6a591f98-89ee-4eee-b5c5-e325b6efe82a.png`
- Implementation screenshot: `E:\DevTools\album_cleaner_workspace\ui-preview\reference-home-final.png`
- Side-by-side comparison: `E:\DevTools\album_cleaner_workspace\ui-preview\reference-home-comparison-final.png`
- State: MED-AL00 Android Release，媒体扫描完成，首页滚动到顶部。

### 视口与归一化

- 参考图：629 × 721 px；没有提供逻辑视口、DPR 或字体缩放信息。
- 真机：720 × 1600 px，Android density 320（约 360 × 800 dp），系统字体缩放 1.15。
- 对比图将参考图按宽度等比放大到 720 px，真机图保持原始 720 × 1600 px，两侧均未拉伸。画板比例不同，因此只比较参考图覆盖区域的结构、层级和视觉语言，不伪造逐像素结论。
- 参考图在“照片总览”后结束；真机图继续显示现有“分类整理”和底部导航，这部分不属于本次参考图复刻范围。

### Findings

- 无剩余 P0/P1/P2 问题。
- [P3] 参考图使用风景演示照，真机页头叠放区和 2 × 2 总览区使用用户当前相册的真实缩略图。这是用户明确要求的数据真实性差异，不应把演示素材写死进产品。
- [P3] 真机为窄屏且系统字体为 1.15 倍，因此“全部照片与视频”换成两行，页面纵向占用比参考画板大；信息完整、无重叠、无截断。

### 五项保真检查

- 字体与排版：品牌、营销标题、副标题、CTA、分区标题、总览标题和数量层级一致；窄屏换行保持完整。
- 间距与布局：恢复 Logo + 品牌名 + 设置、左文案右叠放缩略图、76dp 渐变继续卡、照片总览 2 × 2 缩略图与右侧信息区。
- 颜色与视觉 token：复用项目现有冰蓝/粉色页头背景、蓝紫渐变、白色浮层、蓝色主操作和圆形箭头。
- 图片与资产：Logo 与页头背景使用项目现有资产；七个照片位置均由现有 `allMediaCover` 媒体数据驱动，不使用新增风景素材或静态照片。
- 文案与内容：`相册删除`、`清理重复和无用照片 / 让相册更清爽`、`从上次停下的位置继续整理`、`继续整理`、`照片总览`、`全部照片与视频`均与参考一致；进度和数量来自当前数据。

### 交互验证

- 设置齿轮进入“设置”页。
- “继续整理”进入现有媒体复核页，当前项、日期、胶片条和操作区正常显示。
- “全部照片与视频”进入现有全部媒体网格。
- 未执行删除、清空记录或其他破坏性操作。
- 真机日志未出现 `FATAL EXCEPTION`、`E/flutter`、`RenderFlex` 或未处理异常。

### 本轮 Comparison History

1. 先把参考图结构固化为 Widget 测试；旧首页按预期使新测试失败。
2. 恢复参考图对应布局，只重新声明项目已有 Logo 和页头背景；所有照片仍从当前媒体数据读取。
3. 360dp 回归发现照片总览右栏底部溢出 2dp；将图标后的垂直间距从 8dp 收紧为 6dp 后消除。
4. 真机 Release 构建、安装、同屏比较及设置/继续整理/全部媒体入口均通过。

### 本轮 Implementation Checklist

- [x] 参考图与最终真机截图同屏比较。
- [x] 页头 Logo、品牌名、设置入口和三张动态相册缩略图完成。
- [x] 继续整理卡保持 76dp 高度和现有真实进度。
- [x] 照片总览恢复规则 2 × 2 动态缩略图。
- [x] 360dp 布局无 RenderFlex 溢出。
- [x] `flutter analyze` 通过，完整 68 项测试通过。
- [x] Android Release 构建、安装和关键入口真机验证通过。

## 历史 QA（v0.1.36）

### 对比目标

- Source visual truth: `C:\Users\ADMINW~1\AppData\Local\Temp\codex-clipboard-01641ce2-93f7-4fb4-9f30-019e6dbe3617.png`
- Implementation screenshot: `C:\CodexWork\album_cleaner_workspace\ui-preview\release-v0.1.36-home-final.png`
- Scrolled category screenshot: `C:\CodexWork\album_cleaner_workspace\ui-preview\release-v0.1.36-home-bottom.png`
- Full-view comparison: `C:\CodexWork\album_cleaner_workspace\ui-preview\v0.1.36-home-design-qa-comparison-final.png`
- Focused comparison: `C:\CodexWork\album_cleaner_workspace\ui-preview\v0.1.36-home-categories-comparison-final.png`
- State: Android Release，媒体扫描完成，首页顶部与分类滚动区域。

### 视口与归一化

- 参考图：971 × 1619 px，未提供 CSS viewport 或 device scale factor。
- 真机：MED-AL00，720 × 1600 px，Android density 320（约 360 × 800 dp），系统字体缩放 1.15。
- 全图对比把参考图按宽度无拉伸缩放至 720 px；真机图保持原始 720 × 1600 px。参考图画板比例与 Android 真机比例不同，因此只比较结构、相对层级和组件语言，不对垂直坐标做虚假像素级结论。
- 聚焦对比单独裁取“照片总览 + 分类整理”区域，确保标题、图标、计数和卡片宽度清晰可读。

### Findings

- 无剩余 P0/P1/P2 问题。
- [P3] 真机中的照片来自用户当前相册，因此示例内容是实际截图而不是参考图中的风景照。这是有意的数据真实性差异，不应把演示图写死到产品中。
- [P3] Android 1.15 倍系统字号使整体文字比参考图更醒目，但标题仍保持两行，副标题完整，双列分类的标题和数量均未再截断。

### 五项保真检查

- 字体与排版：沿用系统中文字体；品牌标题、主标题、分区标题、正文和计数层级清晰。主标题固定为两行，副标题完整显示；未发现溢出或省略关键信息。
- 间距与布局：品牌栏、主视觉、76dp 继续整理卡、照片总览、分类整理顺序清晰。首两个分类保持双列，其他分类按用户要求依次整行下排；首页重复的“整理进度”块已按用户要求移除，底部导航不遮挡可滚动内容。
- 颜色与视觉 token：保留参考图的冰蓝背景、蓝紫渐变 CTA、青/紫/薄荷分类色和白色浮层；文字与背景对比清楚。
- 图片与资产：品牌 Logo 使用项目现有 PNG；页头装饰使用独立 raster 资产；照片区域使用真实媒体缩略图；图标使用 Material 图标字体，Release 已禁用错误裁剪，未使用 emoji、文本符号或占位图代替。
- 文案与内容：`相册删除`、`清理重复和无用照片 / 让相册更清爽`、`继续整理`、`照片总览`、`分类整理`、`全部照片与视频`及分类数量均与产品状态一致。

### 交互验证

- 设置图标进入“设置”页并可返回。
- “继续整理”进入现有全部媒体复核页并可返回。
- “全部照片与视频”进入全部媒体列表并可返回。
- “视频”分类进入 9 个项目的视频列表并可返回。
- “我的”页仍显示“待处理 / 待删除队列”，队列功能没有随首页板块一起删除。
- 未执行删除、清空记录或其他破坏性操作。

### Comparison History

1. Pass 1
   - Earlier findings: Release 中 Material 图标显示为方框；品牌 Logo 未正常呈现；主标题在真机上折成三行。
   - Fixes: 使用 `--no-tree-shake-icons` 构建；保留真实 Logo 资产；收紧主视觉高度和标题字号。
   - Evidence: `ui-preview\release-v0.1.35-home-pass1-ready.png` 与后续真机截图。
2. Pass 2
   - Earlier findings: MED-AL00 的 1.15 字体缩放仍使主标题折成三行，副标题末字被照片层覆盖。
   - Fixes: 主标题调整为 17sp、副标题 12sp，并限制文字区不侵入右侧照片。
   - Evidence: `ui-preview\release-v0.1.35-home-final.png` 中标题保持两行，副标题完整。
3. Pass 3
   - Earlier findings: 双列分类卡内图标和箭头占宽过多，`视频`、`截屏`标题不可见，`24 项`换行。
   - Fixes: 仅缩小分类卡内部水平 padding、图标容器、间距和尾部箭头。
   - Evidence: `ui-preview\release-v0.1.35-home-categories.png` 与聚焦同屏对比中，两张双列卡标题和数量均完整。
4. Pass 4
   - Post-fix evidence: 全图与聚焦对比未发现新的 P0/P1/P2 视觉或可用性问题。
5. Pass 5
   - User-directed change: 继续整理卡从 88dp 压缩为 76dp，并移除首页重复的“整理进度 / 待删除队列”区块。
   - Post-fix evidence: `ui-preview\release-v0.1.36-home-final.png` 和 `ui-preview\release-v0.1.36-home-bottom.png`；继续卡信息完整，首页末尾直接结束于分类说明，“我的”页队列入口仍可用。

### Implementation Checklist

- [x] 参考图与最终真机截图同屏比较。
- [x] 顶部主视觉、继续整理、照片总览和分类布局完成。
- [x] 首两类双列，其余分类依次整行下排。
- [x] 继续整理卡压缩为 76dp，首页重复进度块已移除。
- [x] 1.15 倍系统字号下无关键信息截断。
- [x] 关键入口真机可用。
- [x] `flutter analyze` 通过，完整 60 项测试通过。

### Follow-up Polish

- 无阻塞项。后续如需更接近参考图，可只在演示数据环境换用风景类样张；生产环境应继续展示真实相册内容。

final result: passed
