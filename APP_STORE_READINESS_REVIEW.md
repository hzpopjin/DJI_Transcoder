# Pocket Helper 上架前检查

## 2026-09-14 补充：App 名称本地化

- 简体、繁体中文应用语言均显示用户指定的「口袋相机助手」，英文与未支持语言回退为「Pocket Helper」。主应用和实时活动扩展通过 `InfoPlist.strings` 本地化系统名称；应用内标题、引导、WhatsNewKit、提示和离线隐私政策使用同一名称。
- 此次只调整品牌名称，不代表已完成所有界面文案的英文翻译。输出相簿仍保留实际名称 `Pocket Helper`，使用说明引用该真实相簿名称，避免语言切换导致重复相簿或找不到历史输出。
- App Store Connect 的「App 信息 → 名称」需独立配置：简体中文、繁体中文填写「口袋相机助手」；英文和其他已添加语言填写「Pocket Helper」。主要语言使用英文可让缺少本地化的商店元数据回退到英文。此处记录配置要求，未修改 App Store Connect 后台。[Apple 本地化说明](https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information)
- 模拟器 35 项测试通过（30 XCTest + 5 Swift Testing，0 失败），包含语言匹配、系统与应用内名称一致、离线政策资源校验。日志：`/tmp/pockethelper-localized-name-tests.log`。
- 无签名 iOS Release 构建通过，已核对主应用、实时活动扩展的三份名称资源及英文默认值，确认本地化隐私政策进入产物。日志：`/tmp/pockethelper-localized-name-release.log`。保留既有 PhotoLibraryService actor isolation 警告；不代表签名归档、真机或商店验收。

## 2026-09-14 补充：图标、启动引导与 WhatsNewKit

当前工作区包含此前的媒体与隐私整改，以下 2026-09-11 正文是历史检查快照，不能直接视为当前代码仍有全部所列问题。本次聚焦图标、启动流程与功能介绍。

- 已替换用户确认的三色蓝快门图标，尺寸 1024 × 1024、无透明通道；同步欢迎页与 Website 本地图标。
- 已接入系统启动 storyboard、可跳过的三屏使用引导、设置内回看入口，以及 GitHub `SvenTiigi/WhatsNewKit` 2.2.1 的原生 `WhatsNewView`，移除手写 What’s New 排版。
- 引导结束前不会挂载触发扫描的 ContentView；不会在介绍页发起照片授权。首次引导结束同时标记当前版本说明，避免紧接着再弹版本页。
- 最终无签名 iOS Release 构建通过，29 项模拟器测试通过（24 XCTest + 5 Swift Testing，0 失败）。已查看 iPhone 与 iPad 欢迎页、WhatsNewKit 深浅色和最大辅助字号的模拟器截图。
- Release 产物确认包含启动 storyboard、离线隐私政策、App 和 WhatsNewKit 的隐私清单、WhatsNewKit MIT 许可。
- 仍有此前 PhotoLibraryService.swift 的 actor isolation 编译警告；真实媒体完整性、权限恢复、逐按钮交互、签名 Archive、App Store Connect 与真机测试仍需验收。没有上传或提交审核。
- 详见 `Design/IntroductionPreview/README.md`；最终构建日志 `/tmp/pockethelper-whatsnew-release.log`，测试日志 `/tmp/pockethelper-whatsnew-tests.log`，结果 `/tmp/PocketHelper-WhatsNewKit-Tests.xcresult`。

## 2026-09-11 历史检查

检查日期：2026-09-11。范围：DEVELOPMENT.md、当前源码、工程与 Release 产物、现有自动测试、Apple 官方要求。未修改业务代码，未上传或提交审核，未读取 App Store Connect 后台。

结论：建议完成下面的优先整改后再送审。编译成功不能替代隐私合规、媒体完整性及真机验收。

## 一、优先整改

### 1. 缺少 PrivacyInfo.xcprivacy（提交阻断风险）

- 源码和本次 Release App 产物均未发现隐私清单。
- `Pocket Helper/Services/AppSettings.swift:23`、`ProcessingCoordinator.swift:716` 等使用 UserDefaults 保存设置及后台标识，需要声明 Required Reason API 使用理由。
- `MediaTranscoder.swift:407` 还调用文件属性 API，应一并按 Apple 当前 API 清单核对。
- 整改：添加与真实用途对应的隐私清单并确保进入 App bundle；检查扩展实际 API 使用；归档后生成隐私报告并执行上传验证。
- 依据：[Apple UserDefaults 文档](https://developer.apple.com/documentation/Foundation/UserDefaults)、[Required Reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)。

### 2. App 内缺少隐私政策链接（明确审核要求）

- `Pocket Helper/Views/SettingsView.swift:122` 只有“媒体仅在本机处理”等说明；“关于”只有版本，整个 App 未发现隐私政策链接。
- 整改：提供可公开访问的隐私政策 URL，加入设置页，并在 App Store Connect 填写同一政策；说明相册访问、GPS 等媒体元数据的保留、iCloud 原片可能经系统下载、本地历史与临时文件的清理、撤销权限和联系方式。
- “本机处理”不能代替隐私政策。商店后台是否已经填写尚未核验。
- 依据：[审核指南 5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/#privacy)。

### 3. 删除原片前没有重新确认输出存在（数据安全，P1）

- `Pocket Helper/Services/ProcessingCoordinator.swift:400` 仅筛选持久化的 readyToDelete 状态，随后直接删除 sourceLocalIdentifier，没有重新获取 outputLocalIdentifier 对应资产。
- 复现路径：转换成功 → 到系统照片删除压缩副本 → 回 App 点击删除原片。现有状态仍允许继续，并提示“压缩结果已经保存并通过校验”。
- 整改：执行删除前重新检查输出资产可访问、类型/配对资源有效；输出缺失或无法核验时阻止对应原片删除，要求恢复权限或重新转换。保留现有 App 和 PhotoKit 两层确认。
- 这是源码确定的保护缺口；本次未在真机执行破坏性复现。

### 4. 媒体校验不足以支撑当前保留承诺（数据完整性，P1）

- `Pocket Helper/Services/MetadataValidator.swift:49` 检查视频时长、HEVC、音轨存在及宽泛 HDR 标签，但未对比普通视频的输入输出分辨率、方向、实际帧率与 10-bit；音轨也仅检查未全部丢失。
- `MetadataValidator.swift:141` 把 BT.2020 色域标签本身作为 HDR 成立条件，无法区分 BT.2020 SDR 与 HLG/PQ，也没有验证传递函数保持一致。
- `MetadataValidator.swift:10` 对 EXIF/TIFF/GPS 仅检查字典存在，未核对关键字段值、照片方向等。复制动作存在，不代表复制结果已完整验证。
- 影响：这些属性即使退化或缺失，输出仍可能通过校验并进入原片删除列表。此项不是声称现有所有输出已损坏。
- 整改：定义明确的关键字段及允许变化范围，加入源/输出对比和真实媒体样本回归；校验未通过时保留原片。4K60/120 完成真机验收前不应在商店描述中作无条件保证。

### 5. 自动扫描会漏掉新导入的旧素材（核心功能，P1）

- `Pocket Helper/Services/PhotoLibraryService.swift:46` 使用 creationDate 与上次扫描时间比较；`ProcessingCoordinator.swift:114` 随后推进检测时间。
- creationDate 是拍摄时间。先扫描，再从 DJI 导入前一天拍摄的视频，即使视频刚加入 DJI Album，也会被过滤。最近 7 天重置同样无法找回拍摄日期更早的素材。
- 整改：按相簿资产变化/已见标识识别新增素材，单独保留用户“暂不处理”的决定；不要用拍摄时间冒充导入时间。加入“旧素材新导入”和“首次不存在相簿、随后导入”的回归用例。

## 二、建议随首版完善

### 6. 数据库初始化失败会直接闪退（P2）

- `Pocket Helper/PocketHelperApp.swift:39` 在 SwiftData 初始化失败时 fatalError；磁盘不足、数据库损坏或迁移失败会导致无法进入 App。
- 整改：提供可理解的错误页与重试/恢复路径；不要自动删除数据库。对已有数据升级和低空间场景验收。

### 7. 媒体下载不响应 Task 取消（P2）

- `Pocket Helper/Services/PhotoLibraryService.swift:306` 将 writeData 包装为 continuation，没有取消处理；任务暂停/移出依赖该下载先回调结束。
- 大型 iCloud 原片下载时，点击暂停或移出后可能长时间继续占用网络与临时空间。
- 整改：采用可取消的资源请求方案并正确处理 continuation、文件写入及清理竞态；真机限速下载验证取消延迟。

### 8. 用户媒体标识以公开日志输出（P2）

- `Pocket Helper/Utilities/PocketLog.swift:11` 起四个等级全部使用 privacy: .public；`PhotoLibraryService.swift:286` 等把文件名、PhotoKit 标识传入日志。
- 整改：数值性能指标与媒体标识分开；文件名、路径、资产标识使用 private 或脱敏，审查错误描述及后台活动中文件名的展示策略。
- 本次未发现应用自己的媒体上传或分析 SDK；此项不代表已发现向开发者服务器传输数据。

## 三、送审前仍需补齐的验收

- 当前部署支持 iOS 18、iPhone 和 iPad。需补 iOS 18 真机、主力稳定系统真机、iPad 横竖屏/多任务、有限权限、拒绝后恢复权限、iCloud 下载、低空间、HDR/Live Photo、后台过期、杀进程恢复与删除取消/输出丢失验收。
- 文档中的 2026-08-15 基准仅覆盖普通视频；不是以上场景的通过记录。当前自动测试主要验证规则和辅助逻辑，没有完整 PhotoKit 保存/删除或真实媒体管线覆盖。
- `DEVELOPMENT.md:362` 仍写 16 项测试，源码实际有 24 项，应更新文档并记录验收设备、系统、素材参数与结果。
- App Store Connect：核对隐私政策与支持 URL、隐私标签、年龄分级、版权/商标使用、截图（包含所支持 iPad）、版本与构建号、审核联系方式、出口合规及目标地区所需资料。这些字段本次没有后台证据，不能判定已缺失或已完成。
- 审核备注应说明无需 DJI 硬件或账号，手动选择普通照片/视频也能体验；自动扫描依赖 DJI Album，后台持续处理需要 iOS 26。提供可用测试素材或演示步骤。
- 当前代码未见账号、内购、广告追踪；不能据此要求添加账号注销、IAP 或 ATT。只在设备上处理的数据不自动等于商店隐私标签中的“收集”；按真实数据流填写。[Apple 隐私标签解释](https://developer.apple.com/app-store/app-privacy-details/)
- 截至本次查询，2026-04-28 起要求 iOS 26 SDK 或更高。当前产物为 iOS 27 SDK，满足这一最低版本条件；是否为 App Store Connect 当时接受的具体工具链，仍以归档验证为准。[Apple SDK 要求](https://developer.apple.com/cn/news/?id=ueeok6yw)

## 四、本次验证记录

- 检查开始时 Git 工作区干净；业务源码保持不变。
- Release 通用 iOS 无签名构建通过：Xcode 27.0（27A266a），iOS 27.0 SDK，MinimumOSVersion 18.0，版本 1.0（1）。
- 初次沙盒构建因 Swift 宏插件无法启动失败，解除该运行限制后通过，不能把初次环境错误列为源码缺陷。
- AppIcon 为 1024×1024、无透明通道；构建产物具备照片用途说明与 Live Activity 扩展。未发现 Test_Assets 的项目资源引用。
- 现有自动测试 24 项通过、0 失败：iPhone 17 Pro Max 模拟器，iOS 26.2，结果为 TEST SUCCEEDED。这些测试不覆盖上述所有整改项。
- 未完成签名 Archive、Validate App、TestFlight 上传、商店后台核验或本次真机媒体验收；Release build 不等于已获上架验证。
- 构建日志：`/private/tmp/PocketHelper-AppStore-Audit-build.log`；测试日志：`/private/tmp/PocketHelper-AppStore-Audit-tests.log`；测试结果：`/private/tmp/PocketHelper-AppStore-Audit-tests.xcresult`。
