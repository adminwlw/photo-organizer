# Apple 相册查看器交互研究

更新日期：2026-10-26  
范围：iPhone 单张照片/视频查看时的缩放、平移、媒体切换、控件显隐、缩略图带和视频结束状态。  
资料边界：仅引用 Apple Support、Human Interface Guidelines 与 Apple Developer Documentation。Apple 没有公开照片 App 的精确缩放倍率、动画时长、阻尼曲线或视频结束后的内部状态机；这类细节在下文明确标记为“实现推断”。

## 结论摘要

建议把查看器拆成两个互斥状态：

1. **浏览态（适配屏幕）**：允许左右切换媒体；显示日期、数量进度、缩略图带和操作按钮；单击内容切换控件显隐。
2. **沉浸缩放态（比例大于适配比例）**：隐藏所有浮层按钮、进度、缩略图和视频控制；单指只平移当前媒体，不触发左右换片；双击或捏合回适配比例后恢复浏览态。

这符合 Apple 对熟悉手势、直接操控、全屏媒体控件和照片 App 缩略图带的公开说明，同时避免当前“图片已放大但仍触发换片/操作”的手势冲突。

## Apple 官方明确说明

### 1. 双击和捏合缩放

- Apple 的标准手势表把“双击”定义为放大；已放大时再次双击用于缩小。[Apple HIG：Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures/)
- iPhone 使用手册进一步明确：照片可以通过双击或捏合查看细节；再次双击会缩小。[Apple Support：Learn basic gestures to interact with iPhone](https://support.apple.com/en-ie/guide/iphone/iph75e97af9b/ios)
- `UIScrollView` 官方文档说明，捏合时系统同时调整内容比例与偏移，并原生支持缩放和平移；超出边界时默认会回弹。[Apple Developer：UIScrollView](https://developer.apple.com/documentation/uikit/uiscrollview)
- `UIPinchGestureRecognizer` 的比例是连续变化值。Apple 特别提醒，不应把每次回调的累计比例反复乘到已经缩放的内容上，否则会产生指数式放大；应以手势开始值为基准，或每次应用后把增量比例重置为 `1.0`。[Apple Developer：Handling pinch gestures](https://developer.apple.com/documentation/uikit/handling-pinch-gestures)

### 2. 平移与缩放属于同一直接操控

- `UIScrollView` 同时提供 `panGestureRecognizer` 和 `pinchGestureRecognizer`，用内容偏移、缩放比例及边界处理共同实现缩放后的平移。[Apple Developer：UIScrollView](https://developer.apple.com/documentation/uikit/uiscrollview)
- Apple 对平移手势的定义是跟随手指移动并即时更新对象或内容；HIG 要求手势尽量即时响应并持续提供可预测反馈。[Apple Developer：Handling pan gestures](https://developer.apple.com/documentation/uikit/handling-pan-gestures)、[Apple HIG：Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures/)

### 3. 照片 App 的换片、缩略图带和控件显隐

- Apple 照片使用手册明确：打开单张照片后，可在主图上左右轻扫继续浏览，也可以横向滑动照片下方的缩略图，快速向前或向后跳转。[Apple Support：View photos and videos on iPhone](https://support.apple.com/en-ie/guide/iphone/iph3d267610/ios)
- 同一页面明确：单击正在查看的照片可隐藏屏幕控件，再次单击恢复显示。[Apple Support：View photos and videos on iPhone](https://support.apple.com/en-ie/guide/iphone/iph3d267610/ios)
- HIG 要求熟悉的手势按用户预期工作，并建议快捷手势只补充、不要替代可见控件。[Apple HIG：Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures/)

### 4. 视频控制

- Apple 照片使用手册展示并说明：视频查看界面的播放/暂停按钮、进度条和静音/音量按钮位于画面下部；播放时可以暂停，也可拖动进度条前后跳转。[Apple Support：View photos and videos on iPhone](https://support.apple.com/en-ie/guide/iphone/iph3d267610/ios)
- HIG 建议优先采用系统视频播放器；确需自定义播放器时，也应参考系统播放器的行为和界面，避免破坏用户习惯。[Apple HIG：Playing video](https://developer.apple.com/design/human-interface-guidelines/playing-video)
- Apple 的全屏设计指南允许临时隐藏工具栏和导航控件，但要求播放控件持续可用或容易重新唤出。[Apple HIG：Going full screen](https://developer.apple.com/design/human-interface-guidelines/going-full-screen)
- Apple 的能耗指南说明，`AVPlayerViewController` 的标准视频控件会在媒体播放期间自动隐藏。[Apple Developer：Restrict UI When Playing Full-Screen Video](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/HideControlsInFullScreenVideo.html)
- AVFoundation 会在播放项目到达结尾时发送 `AVPlayerItem.didPlayToEndTimeNotification`，应用可以据此实现结束状态。[Apple Developer：AVPlayerItemDidPlayToEndTimeNotification](https://developer.apple.com/documentation/avfoundation/avplayeritem/didplaytoendtimenotification)

## 面向本项目的实现推断

以下是基于上述官方原则和用户当前需求的工程选择，不是 Apple 对照片 App 内部实现的公开承诺。

### 缩放与平移

- 初始状态使用“完整显示媒体”的适配比例，并把它视为逻辑比例 `1.0`。
- 捏合应围绕双指焦点连续缩放，而不是围绕屏幕中心跳变；缩放范围可先保持项目现有的 `1.0–4.0`，无需为模仿 Apple 另加参数。
- 双击适配态时，以点击位置为焦点动画放大到约 `2.5x`；已放大时双击动画回 `1.0`，同时把偏移归零。
- 平移边界必须按**媒体实际适配后的可见矩形**计算，而不是按整块屏幕计算。竖图、横图和带留白视频的可移动范围不同；按屏幕宽高计算会产生明显空白或无法移到图片边缘。
- 缩放回到 `1.0` 附近时归一化为精确 `1.0 + Offset.zero`，避免浮点余量让界面误判为仍在放大。
- 切换到下一项时重置缩放和偏移。不要把上一张的倍率或位置带给下一张。

### 手势优先级

- 适配态：单指水平滑动负责换片；项目已有的上下整理手势保持原意。
- 放大态：单指只平移媒体，禁止水平换片和上下整理；双指继续缩放。
- 从放大态缩回适配态后，下一次新的单指手势才重新参与换片/整理，避免同一次缩放结束误触动作。
- 单击显隐控件不能抢占双击；应等待双击判定失败后再执行单击，或用同一个手势系统协调。

### 沉浸显示

- 一旦缩放比例明显高于 `1.0`，隐藏顶部返回、数量/日期、待删除入口、缩略图带、收藏/撤销以及视频控制；回到 `1.0` 后恢复。
- 若只想临时专注内容，适配态下仍可通过单击主图切换全部控件显隐。这一条有 Apple 照片用户手册的直接依据。
- 控件隐藏应使用短淡入淡出，不要改变媒体布局尺寸，否则缩放过程中画面会跳动。

### 横向缩略图带

- 放在主图与底部收藏/撤销之间；当前缩略图略大或有高对比描边，其余保持中等尺寸。
- 点按缩略图直接切换；横向拖动缩略图带只滚动列表，不触发主图的整理手势；切换后让当前项平滑滚到可见区域或居中。
- 快速切换只预取邻近小缩略图，不预先解码整组原图/视频。Apple 公开确认的是“缩略图带可快速跳转”，没有公开尺寸和预取数量，因此这些值应按本项目性能测试确定。

### 视频控制与播放结束

- 浏览态下把视频进度/播放控制固定在缩略图带和收藏/撤销区域之上，位置不随视频画幅跳动；同时保留足够对比度和点击热区。
- 播放或放大时可隐藏非必要操作；单击画面应能重新显示播放控制，满足“容易唤出”。
- 用户明确要求视频播完回到起始封面：监听播放器结束事件，暂停并 `seek(Duration.zero)`，显示原缩略图/首帧和居中播放按钮；下次点按从头播放。
- Apple 只公开了“如何检测播放结束”，没有在上述资料中明确说明照片 App 一定回到起始封面。因此这是符合用户需求的产品决定，不应写成 Apple 的固定行为。

## 可验收行为清单

1. 双击任意照片区域，放大围绕落点发生；再双击恢复完整显示和零偏移。
2. 捏合缩放跟手且无指数式跳变；松手时不超过上下限，越界能平滑回弹或归位。
3. 放大后能平移到媒体四边，但不能拖出超过媒体边界的大块空白。
4. 放大态的水平/垂直单指手势不会换片、删除或待定；回到适配态后这些手势恢复。
5. 放大照片或视频时，所有浮层控件和图标隐藏；还原后恢复。
6. 适配态单击主图可显隐控件，再次单击恢复。
7. 缩略图带支持横向快速滚动和点按跳转，当前项视觉突出；切换后缩放归位。
8. 视频控制条固定在收藏/撤销上方，不因横竖视频比例改变位置。
9. 视频播放结束后显示起始封面和播放按钮，点按后从 `0:00` 重新播放。

## 资料未能证明的细节

- Apple 照片 App 双击后的准确倍率。
- 双击、复位、控件显隐和缩略图滚动的准确毫秒时长与缓动曲线。
- Apple 照片 App 在所有 iOS 版本中视频播放结束后的准确画面与按钮状态。
- Apple 照片 App 缩略图尺寸、间距和预取窗口。

因此实现时应以本项目现有动画风格、真实 iPhone 手感和自动化回归为准，不应声称是对 Apple 私有实现的精确复刻。
