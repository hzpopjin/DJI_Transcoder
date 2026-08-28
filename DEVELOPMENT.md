# Pocket Helper 开发文档

本文档记录 Pocket Helper 的当前实现、关键约束、调试方法与后续开发约定。修改媒体管线、PhotoKit 保存逻辑或后台任务前，请先阅读对应章节。

## 1. 项目定位

Pocket Helper 是最低支持 iOS 18 的 SwiftUI App，用于将 DJI 相机素材压缩为更适合手机相册存储和分享的格式：

- 普通照片输出 HEIF/HEIC。
- 普通视频输出 HEVC MOV。
- Live Photo 输出配对的 HEIF 与 HEVC MOV，并在照片图库中仍表现为一个 Live Photo。
- 尽可能保留公开 API 可读取和写入的 EXIF、TIFF、GPS、QuickTime、HDR 与 Live Photo 元数据。
- 输出先完成文件级校验，再保存到照片图库和 `Pocket Helper` 专用相簿。
- 只有成功保存且校验通过的任务才允许删除原片。

项目仅使用 Apple 原生框架：SwiftUI、SwiftData、PhotoKit、AVFoundation、Image I/O、BackgroundTasks、ActivityKit、WidgetKit 和 OSLog。

## 2. 工程配置

- App target：`Pocket Helper`
- App 中文显示名：`口袋相机助手`；“口袋相机”作为完整概念，不在图标中单独使用口袋或包袋符号。
- Test target：`Pocket HelperTests`
- Live Activity extension target：`Pocket Helper Live Activity`
- Bundle identifier：`com.jilllees.djihelper`
- Deployment target：iOS 18.0
- 默认 Swift actor isolation：`MainActor`
- 输出视频容器：MOV
- 来源相簿：`DJI Album`
- 输出相簿：`Pocket Helper`
- 后台任务通配标识：`com.jilllees.djihelper.transcode.*`
- 完成实时活动保留时间：120 秒

### App 图标资源

- 当前正式图标继续使用早期的深蓝色立体版本，源图备份在 `Design/AppIcon-Early-Original.png`，实际构建文件为 `Pocket Helper/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`。
- `Design/AppIcon-Light-Concept.png` 是基于早期图标生成的浅色背景原始稿；`Design/AppIcon-Light-Alternate.png` 是规范化为 1024×1024、无透明通道的 AppIcon 备选版本，当前不参与构建。
- `Design/AppIcon-Source.svg` 是后续制作的扁平矢量方案，作为设计备选保留，当前不参与构建，不应因切回早期图标而删除。
- 图标的固定识别元素是“六叶镜头光圈 + 双段环形转换箭头”；不要增加单独表达“口袋”的图形。
- 正式 AppIcon 必须为 1024×1024、无透明通道，并由 `AppIcon.appiconset/Contents.json` 引用。切换备选图标时，应先复制到正式构建文件，再执行 Release 构建验证。

`PocketHelper-Info.plist` 必须保留：

- Photo Library 读写用途说明。
- `processing` background mode。
- `BGTaskSchedulerPermittedIdentifiers` 中的动态任务通配标识。
- `NSSupportsLiveActivities = true`。
- `pockethelper://` URL scheme，用于实时活动点击后打开 App。

## 3. 目录结构

```text
Pocket Helper/
├── PocketHelperApp.swift          App、服务和 SwiftData 初始化
├── ContentView.swift              生命周期、全局弹窗和 Tab 容器
├── Models/
│   ├── DomainModels.swift         媒体类型、状态、设置枚举和管线值类型
│   └── PersistenceModels.swift    MediaJob 与 AppMessage SwiftData 模型
├── Services/
│   ├── AppSettings.swift          UserDefaults 设置
│   ├── CompletionActivityManager.swift 完成实时活动创建与清理
│   ├── PhotoLibraryService.swift  授权、扫描、下载、保存和删除
│   ├── MediaTranscoder.swift      HEIF、HEVC 与 Live Photo 转码
│   ├── MetadataValidator.swift    文件、HDR 与 Live Photo 校验
│   ├── ProcessingCoordinator.swift 队列、恢复、后台任务与进度
│   └── MessageCenter.swift        横幅和持久化消息入口
├── Utilities/
│   ├── FilenameGenerator.swift
│   ├── Formatters.swift
│   └── PocketLog.swift
└── Views/
    ├── DashboardView.swift
    ├── HistoryView.swift
    ├── SettingsView.swift
    ├── MessageCenterView.swift
    ├── AssetThumbnailView.swift
    └── BannerView.swift
Pocket Helper Shared/
└── CompletionActivityAttributes.swift App 与扩展共享的 ActivityKit 数据结构
Pocket Helper Live Activity/
├── CompletionLiveActivity.swift  锁屏和灵动岛完成态界面
├── PocketHelperLiveActivityBundle.swift
└── Info.plist
Design/
├── AppIcon-Early-Original.png     当前正式图标的原始备份
├── AppIcon-Light-Concept.png      浅色背景生成原始稿
├── AppIcon-Light-Alternate.png    浅色背景备选图标
└── AppIcon-Source.svg             保留的扁平矢量备选方案
```

## 4. 核心数据流

```text
PhotoKit 扫描/手动选择
        ↓
MediaAssetDescriptor
        ↓ 用户确认或自动转换设置
SwiftData MediaJob 队列
        ↓
下载 PhotoKit 原始资源到临时目录
        ↓
MediaTranscoder 转码
        ↓
MetadataValidator 文件级校验
        ↓
PhotoLibraryService 保存到相册
        ↓
保存后校验（Live Photo 必须被 PhotoKit 识别）
        ↓
readyToDelete / completed
```

临时文件位于系统临时目录下的 `PocketHelper/<asset identifier>/`。任务成功、失败、取消或移出队列时都应清理对应目录。

## 5. 扫描规则

### 自动扫描

- 仅在 PhotoKit 完整 `.authorized` 权限下运行。
- 只扫描 `DJI Album`。
- 首次检测从当天零点开始；之后只扫描持久化的“上次检测时间”之后新增、尚未记录到 SwiftData、且不属于输出相簿的素材。
- 设置中可将自动检测范围切换为“照片”“视频”或“照片和视频”；“照片”同时包含普通照片和 Live Photo。
- App 启动时扫描一次。
- 只有 App 真正进入过后台，随后回到前台时才再次扫描。
- 自动扫描有 45 秒冷却，避免系统弹窗、控制中心和快速切换造成重复查询。
- 每次检测完成都会推进“上次检测时间”；用户在预览中选择“暂不处理”时，这批素材不会在后续自动检测中再次出现，只能手动选择或使用“重置检测最近 7 天”。

### 系统版本与后台处理

- iOS 26 及以上使用 `BGContinuedProcessingTask` 在 App 离开前台后继续转换。
- iOS 18–25 保留完整的照片、视频和 Live Photo 转码能力，但不提交持续后台任务；系统暂停 App 后，再次打开 App 可继续队列。

### 视频目标码率

- 均衡档基准为 4K30 16 Mbps、1080P30 6 Mbps、720P30 2 Mbps，中间分辨率按像素数插值。
- 60 fps 相对 30 fps 提高 50%，120 fps 提高 100%；中间帧率平滑插值。
- 节省空间档使用基准的 80%，高质量档使用基准的 125%。
- 4K60 与 4K120 在读取原片参数后弹出实验性确认，确认后保留输入帧率继续 HEVC 转换。

### 强制扫描

首页“扫描”按钮和下拉刷新使用 `scanForNewAssets(force: true)`，不受冷却限制。

### 最近 7 天扫描

只有设置中的“重置检测”会扫描今天及之前六个自然日，并沿用当前选择的自动检测范围。发现素材后仍按自动转换设置决定是直接入队还是等待用户确认。确认 popover 直接锚定在“重置检测最近 7 天”按钮上方，不使用屏幕固定位置。

### 有限权限

PhotoKit `.limited` 权限下不自动扫描相簿，只允许用户使用 PhotosPicker 手动选择可见素材。

### 手动选择与来源确认

- SwiftUI `PhotosPicker` 必须显式传入 `PHPhotoLibrary.shared()`，并使用 `.current` 编码策略，避免 Live Photo 被兼容转换或失去图库关联。
- 正常路径直接使用 `PhotosPickerItem.itemIdentifier`。如果系统返回 `nil`，尝试加载 `PHLivePhoto`，再从 `PHAssetResource.assetResources(for:)` 的 `assetLocalIdentifier` 恢复原始资产标识。
- 位于 `DJI Album`，或文件名具有明确 DJI 特征的素材标记为 DJI 来源。
- 其他来源的普通照片、视频和 Live Photo 仍然支持转换，但必须进入确认页；即使开启自动转换也不会跳过这次确认。
- 确认页显示非 DJI/Pocket 数量，并将对应行标为“非 DJI/Pocket 素材”。
- 已存在的任务、`Pocket Helper` 输出副本和无法读取的项目会显示横幅并写入消息中心，不允许静默无响应。
- 只有直接标识和 Live Photo 配对资源回退都失败时，才提示用户确认素材已保存到系统相册、iCloud 原片已下载及权限状态。

## 6. 转换启动规则

- `扫描后自动转换` 默认关闭。
- 默认模式下，扫描结果只进入预览页，用户点击“开始转换”后才创建队列任务。
- 开启自动转换后，新发现素材会直接加入队列并开始处理。
- 非 DJI/Pocket 素材始终需要用户点击“仍要转换”。
- 手动暂停后，任务状态为 `paused`；再次点击“继续转换”才恢复。
- 后台任务过期或系统取消使用相同的暂停语义，不能记录成转码失败。

## 7. 队列状态

主要状态转换：

```text
queued → downloading → transcoding → validating → saving
                                             ├→ readyToDelete
                                             └→ completed

任意安全点 → paused
无体积收益 → skipped
不可恢复错误 → failed
```

约束：

- 同一时间只运行一个队列处理 Task。
- 一次只转码一个高分辨率视频。
- 队列循环使用 asset identifier 快照，不长期持有可能被界面删除的 SwiftData 对象。
- “移出队列”只删除 SwiftData 任务和临时文件，不删除 PhotoKit 原片。
- 历史页只展示非活动状态的记录；“清空”会在确认后删除这些 SwiftData 记录及其临时文件，不会删除系统相册中的照片或视频。
- 重试默认只重置为 `queued`；只有自动转换开启时才立即执行。

## 8. 视频管线

`MediaTranscoder.exportHEVC` 使用 `AVAssetExportSession` 和 `AVAssetExportPresetHEVCHighestQuality`：

- 输出 MOV/HEVC。
- 保留方向、时长、帧率、音轨、顶层 metadata 和兼容的 metadata tracks。
- 目标码率使用 720P30、1080P30、4K30 三个锚点，按输出像素数插值，并按实际帧率调整。
- HDR 缩放时使用 `perFrameHDRDisplayMetadataPolicy = .propagate`。
- Live Photo 动态资源的 metadata tracks 必须完整复制，以保留 `still-image-time`。

当前质量参考值：

| 档位 | 720P30 | 1080P30 | 4K30 |
| --- | ---: | ---: | ---: |
| 节省空间 | 1.6 Mbps | 4.8 Mbps | 12.8 Mbps |
| 均衡 | 2 Mbps | 6 Mbps | 16 Mbps |
| 高质量 | 2.5 Mbps | 7.5 Mbps | 20 Mbps |

60 fps 使用对应 30 fps 码率的 150%，120 fps 使用 200%。

验证至少包括：

- 输出存在 HEVC 视频轨道。
- 时长误差不超过 0.12 秒。
- 输入为 HDR 时输出仍具有 HDR 色彩描述。
- 输入含音轨时输出不能丢失全部音轨。
- Live Photo 动态部分不能超过用户设置的尺寸上限。

## 9. 照片与 HDR

普通照片和 Live Photo 静态资源通过 Image I/O 写入 HEIC：

- 复制可迁移的图像属性和 metadata。
- 保留 EXIF、TIFF、GPS 与 XMP。
- 保留 HDR gain map、深度、视差和人像蒙版等辅助图像数据。
- 普通照片输出不小于原片时标记为 `skipped`，不保存副本。
- Live Photo 即使总大小未降低也保留配对结果，并记录警告，避免破坏 Live Photo 功能。

当前照片质量：0.65、0.82、0.92，默认 0.82。

## 10. Live Photo 不变量

Live Photo 保存前必须满足：

1. HEIC Maker Apple metadata 的键 `17` 包含新的 content identifier。
2. MOV 的 `com.apple.quicktime.content.identifier` 与 HEIC 完全一致。
3. MOV metadata tracks 中存在 `com.apple.quicktime.still-image-time`。
4. 静态资源使用 `.photo`，动态资源使用 `.pairedVideo`，并在同一次 `PHAssetCreationRequest` 中添加。
5. 两个资源使用相同主文件名 stem。

保存后必须再次从 PhotoKit 获取新资产并确认：

- `mediaSubtypes` 包含 `.photoLive`。
- 资源列表同时包含 `.photo` 和 `.pairedVideo`。

如果保存后校验失败，立即删除刚创建的无效输出；原片和原任务不可进入删除列表。

## 11. 后台任务与实时活动

处理队列运行期间，App 从 active 进入 inactive 时提交 `BGContinuedProcessingTaskRequest`。系统负责处理中的锁屏实时活动和支持设备上的灵动岛展示。

实现约束：

- 每次请求使用精确 UUID 标识，例如 `com.jilllees.djihelper.transcode.<UUID>`。
- 必须先为精确标识注册 handler，再提交请求。
- 待处理标识写入 UserDefaults，App 下次启动时先恢复 handler。
- 只保留一个有效的已提交请求，清理重复或过期标识。
- 系统 expiration handler 只暂停队列并清理当前临时输出。
- App 在前台先完成时，取消尚未启动的后台请求。
- 后台队列完成后，先生成 ActivityKit 完成态，再结束持续后台任务：成功为绿色勾选，部分失败为橙色提示。
- 完成态使用 `.after(Date.now + 120)`，最多保留两分钟；用户可提前划掉。
- App 启动或重新进入 active 时调用 `CompletionActivityManager.dismissAll()` 立即清除完成态。
- ActivityKit 被用户关闭或系统拒绝启动时只记录 warning，不延迟 `BGContinuedProcessingTask.setTaskCompleted`，也不虚报仍在转码。

不要恢复旧的“后台继续”按钮。后台提交由生命周期自动触发，但只有正在处理任务时才执行。

## 12. 保存与删除安全

- 输出必须先通过文件级校验，之后才能调用 PhotoKit 保存。
- 保存成功后记录输出 asset identifier。
- `保存后删除原片` 默认开启，但只表示完成后提供删除操作，不允许静默删除。
- 完成后转换页状态卡显示普通红色文本行“删除 N 个原片”，不会自动弹出气泡。
- 用户点击删除行后先显示标准系统 Alert，之后 PhotoKit 仍会显示系统确认。
- 删除列表只包含 `readyToDelete`。
- `failed`、`paused`、`skipped`、未保存或校验失败任务不得进入删除列表。
- Live Photo 原片按一个 `PHAsset` 删除，不分别删除 HEIC/MOV 资源。

删除确认的展示状态属于 `ContentView` 局部 `@State`。协调器只在用户点击删除行后通过 `deleteConfirmationRequestID` 发送一次性事件，避免 SwiftUI 在视图更新期间直接写 `@Published` 状态。

## 13. 文件名

支持：

- 原名加后缀，默认 `_Compressed`。
- App 独立自动编号 `PH_######`。
- 自定义模板：`{original}`、`{date}`、`{time}`、`{counter}`、`{media}`。

扩展名由真实输出格式决定。非法字符会被清理，冲突追加 `_2`、`_3`。Live Photo 静态和动态资源必须共用 stem。

## 14. SwiftData

App 启动时先确保 `Application Support` 目录存在，再创建默认 `ModelContainer`。不要随意修改默认 store URL，否则已有安装的任务历史可能看起来丢失；如果必须迁移路径，需要先设计显式迁移。

持久化模型：

- `MediaJob`：输入/输出标识、文件名、状态、进度、大小、错误和重试次数。
- `AppMessage`：严重性、任务标识、阶段、详情、错误码、未读状态和可执行动作。

修改 `@Model` 字段时，需要评估现有数据库迁移，不要只验证全新安装。

## 15. 日志和诊断

统一使用 `PocketLog`，subsystem 为 App bundle identifier，category 为 `PocketHelper`。

日志等级：

- `debug`：轨道数量、状态跳过、文件级校验结果。
- `info`：用户动作、扫描、阶段切换、输入输出参数和耗时。
- `warning`：后台过期、私有元数据无法迁移、可恢复异常。
- `error`：任务失败、保存失败、后台 handler 注册失败。

每个视频会记录：

- 输入尺寸、时长、帧率和目标码率。
- 输出大小、实际平均码率和 AVFoundation 导出耗时。
- 下载、转码与校验、PhotoKit 保存、任务总耗时。
- HEVC、HDR、输出尺寸和音轨校验结果。

每个 Live Photo 还会记录 content identifier 配对、`still-image-time` 和 metadata track 校验结果。

日志中不要记录照片内容、完整定位或用户隐私数据。诊断导出应继续隐藏精确位置。

## 16. 构建与测试

当前开发环境使用 `Xcode-beta.app`。如果 `xcode-select` 仍指向 CommandLineTools，可直接指定 `DEVELOPER_DIR`。

通用真机构建：

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild \
  -project DJI_Transcoder.xcodeproj \
  -scheme "Pocket Helper" \
  -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

模拟器测试：

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild \
  -project DJI_Transcoder.xcodeproj \
  -scheme "Pocket Helper" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2" \
  test
```

当前自动测试覆盖：

- 文件名规则、模板清理和 Live Photo 同 stem。
- 当天与最近 7 天日期窗口。
- 自动转换默认关闭。
- 自动检测默认选择视频，以及三种检测范围对照片、视频、Live Photo 的匹配规则。
- 动态持续后台任务标识注册。
- 自动扫描首次允许、冷却期拒绝和冷却结束后允许。
- 完成实时活动的两分钟保留策略与成功/失败数量状态。

当前完整测试共 16 项。

## 17. Test_Assets 约束

根目录 `Test_Assets/` 只用于开发者手动导入模拟器或真机：

- 不得加入 App target Resources。
- 不得加入测试 Bundle Resources。
- 不得通过运行时路径依赖该目录。
- 验证 Live Photo 时，HEIC 与 MOV 必须成对导入或通过专用调试脚本处理。

提交前可检查：

```sh
rg -n "Test_Assets" DJI_Transcoder.xcodeproj PocketHelper-Info.plist
```

预期不应出现资源构建引用。

## 18. 真机验收清单

每次修改媒体或后台管线后至少验证：

- DJI 4K HLG/PQ 视频保持分辨率、方向、实际帧率、HEVC、10-bit 和 HDR 色彩标签。
- 输出平均码率与设置档位相符，且主观画质可接受。
- 普通照片尺寸、方向、时间、GPS、Make/Model、曝光和焦距一致。
- HDR 照片 gain map 或扩展动态范围仍存在。
- 三档 Live Photo 动态尺寸均可保存为可播放的 Live Photo。
- 将检测范围设为“照片”或“照片和视频”后，当天自动扫描和最近 7 天重置扫描都能发现 `DJI Album` 内的 Live Photo。
- 手动选择 iPhone 等非 DJI Live Photo 时先显示来源确认，再完成配对保存。
- 暂停、移出当前任务、重置、失败重试和杀进程恢复。
- 前台处理、进入后台、实时活动、系统取消和 expiration 恢复。
- 后台完成后灵动岛显示勾选，约两分钟后消失；期间打开 App 应立即清除。
- 删除确认取消与确认，确保删除列表不包含失败或未保存任务。
- iCloud 原片下载、磁盘不足、有限权限和无空间收益。

## 19. 2026-08-15 真机基准

一次 iPhone 17 Pro Max、iOS 27 beta 调试运行中，9 个普通视频成功处理：

- 原始总大小约 618.0 MB。
- 输出总大小约 142.5 MB。
- 节省约 475.5 MB，体积降低约 76.9%。
- 队列端到端耗时约 34.2 秒。

该结果只覆盖普通视频，不能替代 HDR 标签、视觉质量和 Live Photo 配对验收。

当次日志还包含 iOS 27 beta 的 GlassPopover 约束、QuartzCore handler 和 System Gesture Gate 系统噪声。若没有界面异常或崩溃，优先在 iOS 26 和更新系统 seed 上交叉验证，不要直接把系统 beta 日志当作 App 故障。

## 20. 已知边界与后续方向

- DJI 私有 metadata 不一定能通过公开 API 重建；关键字段缺失必须阻止删除，非关键字段记录警告。
- AVAssetExportSession 的 `fileLengthLimit` 是目标约束，不保证精确码率；实际码率必须从输出大小和时长复算。
- 后台执行时长由系统决定，App 必须始终支持安全暂停与下次恢复。
- `BGContinuedProcessingTask` 本身没有可配置的完成后保留策略，因此完成态由独立 ActivityKit extension 接力；不要通过延迟 `setTaskCompleted` 冒充仍在处理。
- iCloud 下载速度和可用性不受 App 控制。
- `.xcresult` Launch 日志通常没有内存、能耗或热状态指标；需要性能结论时使用 Instruments、Xcode Organizer 或 MetricKit。
- 后续建议为 `PhotoLibraryService` 和 `MediaTranscoder` 抽象协议，以便对扫描、取消、保存失败和恢复编写隔离测试。

## 21. 修改原则

- 媒体输出在保存前必须验证，不能为了“尽量成功”跳过关键校验。
- 原片删除必须保持用户确认和 PhotoKit 系统确认两层保护。
- 新增自动行为时必须尊重“自动转换默认关闭”。
- 所有长任务都必须正确响应 cancellation，并在取消后清理临时文件。
- 修改后台任务标识时，同时更新 Info.plist、注册逻辑和测试。
- 修改 Live Photo 时同时验证文件级结构与 PhotoKit 保存后的资产类型。
- 提交前至少执行通用 iOS 构建、完整单元测试和 `git diff --check`。
