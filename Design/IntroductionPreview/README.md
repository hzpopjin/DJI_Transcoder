# Pocket Helper 启动与版本介绍

## 最终实现

- 图标采用用户确认的 `Design/AppIconConcepts/H-three-solid-blues.png`，保留六叶快门和双箭头。AppIcon 规范化为 1024 × 1024、不含透明通道；欢迎页和 Website 的图标同步更新。
- 系统启动页使用 `LaunchScreen.storyboard`：纯色背景和居中的品牌图标，不人为延长启动时间。
- 首次使用显示三屏引导：支持的媒体、设置与转换步骤、本地处理与原片确认。可直接开始，也可在设置中重新查看；引导结束后才创建主界面、启动扫描。
- What’s New 使用 [SvenTiigi/WhatsNewKit](https://github.com/SvenTiigi/WhatsNewKit) **2.2.1** 的 `WhatsNewView`。没有保留手写版本亮点页面。`AppReleaseNotesView` 仅配置文案、功能图标、颜色、间距及按钮回调。
- What’s New 的“查看使用指南”通过库的 secondary action 打开引导；主按钮进入 App，设置中的回看按钮则关闭当前介绍。
- 首次引导完成会同时标记当前版本说明为已看，避免连续弹两次介绍。后续更新版本说明后展示一次。设置中可随时手动查看。
- 使用中文文案、三档蓝色和适配深色模式的语义颜色；滚动内容支持动态字体，欢迎引导在辅助功能字号下采用纵向图文与按钮布局。

## 维护

- `Pocket Helper/Models/AppIntroduction.swift`：介绍显示规则和版本标识；发布新版本说明时更新 `releaseVersion`。
- `Pocket Helper/Views/AppIntroductionView.swift`：启动入口与首次使用指南。
- `Pocket Helper/Views/AppReleaseNotesView.swift`：WhatsNewKit 内容配置；同步修改版本对应文案。
- `DJI_Transcoder.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`：锁定 WhatsNewKit 2.2.1，revision `6157c77e8be9b3d2310bc680681b61a8d9e290ac`。
- 库的 MIT 许可随 App 以 `WhatsNewKit-LICENSE.txt` 打包，库的隐私清单由 SwiftPM 资源包带入。

## 验证边界

2026-09-14，WhatsNewKit 接入后重新验证：

- Xcode 27.0，通用 iOS 无签名 Release 构建通过。
- iPhone 17e / iOS 27.0 模拟器测试通过：24 项 XCTest + 5 项 Swift Testing，共 29 项、0 失败。其中新增 5 项覆盖首次引导、已读版本、版本更新和未完成引导的显示规则。
- 实际查看欢迎页（iPhone、iPad mini）、WhatsNewKit 浅色/深色页面，以及最大辅助功能字号的初始视口；按钮可见，内容可滚动。尚未完成逐按钮 UI 自动化、VoiceOver 朗读和真机验收。
- Release bundle 包含启动 storyboard、App 与 WhatsNewKit 的隐私清单、库 MIT 许可和离线隐私政策；AppIcon 为 1024 × 1024、不含 alpha。
- 日志：`/tmp/pockethelper-whatsnew-release.log`、`/tmp/pockethelper-whatsnew-tests.log`；测试结果：`/tmp/PocketHelper-WhatsNewKit-Tests.xcresult`。

本目录保存模拟器实际截图。构建、测试与截图不等于真实媒体管线、签名 Archive 或 App Store Connect 验证。此次没有上传或提交审核。

现有 PhotoLibraryService 的取消回调仍有 actor isolation 编译警告，属于此前的媒体服务修改，未在这次图标与介绍页工作中改变。
