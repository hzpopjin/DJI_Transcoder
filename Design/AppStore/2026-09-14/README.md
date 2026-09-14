# App Store Connect 中文展示素材

上传时按文件名 01 → 02 → 03 排序。

| 目录 | 用途 | 数量 | 尺寸 |
| --- | --- | --- | --- |
| iPhone-Posters | iPhone 6.9 英寸展示海报 | 3 | 1320 × 2868 |
| iPad | iPad 13 英寸原生截屏，无海报装饰 | 3 | 2064 × 2752 |
| iPhone-Raw / iPad-Raw | 模拟器原始 PNG，供核对及后续制作 | 各 3 | 对应设备原始尺寸 |
| Generated-Originals | 生图工具原始海报，供复用 | 3 | 生图工具返回尺寸 |

三张主题依次为：核心功能介绍、所选素材确认、压缩质量与原片设置。中文 App 名称为「口袋相机助手」。此包按中文商店准备，不包含其他语言翻译或预览视频。

## 来源与生成

- 实际运行设备：iPhone 18 Pro Max、iPad Pro 13-inch (M5)，iOS 27 模拟器。中文、浅色、9:41 状态栏。
- 页面使用当前 App 的 AppIntroductionView、InitialScanPreviewView、SettingsView。素材确认页读取项目 Test_Assets 中的三张真实测试照片（0009、0010、0015），文件体积、尺寸与预计输出均由 App 生成。预计输出不是实测压缩承诺。
- 使用临时 Debug 导航入口定位页面；该入口已从正式源码移除。参考入口保存在 Tools/AppStoreCaptureView.swift，不属于 App target。未生成虚构的转换成功记录或节省空间统计。
- iPhone 海报使用内置 image_gen 工具，逐张以对应原始截屏作为输入。提示词及修正说明见 PROMPTS.md。图像生成可能重绘屏幕细节，原生 PNG 作为界面核对依据保留。
- 上传文件用 sips 统一尺寸并导出最高质量 JPEG，移除透明通道；不额外绘制或替换界面。iPad 保留截图原始尺寸。

## 上传与检查

- 使用 iPhone-Posters 内三张 JPEG 上传 iPhone 6.9 英寸栏；iPad 内三张 JPEG 上传 iPad 13 英寸栏。不要把原始 PNG 和海报重复上传。
- 已按 [Apple 截屏规范](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) 核对上述尺寸及无透明通道要求。
- 本次仅生成本地素材，没有向 App Store Connect 上传或提交审核。

构建日志：`/tmp/pockethelper-appstore-capture-build.log`。正式源码保留此前已完成的名称本地化、保留原片及队列修复。
