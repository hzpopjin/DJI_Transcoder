import SwiftUI
import WhatsNewKit

/// Content and theme configuration only; WhatsNewKit owns the page and its actions.
struct AppReleaseNotesView: View {
    var isReplay = false
    let onFinish: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        WhatsNewView(
            whatsNew: releaseNotes,
            layout: WhatsNew.Layout(
                showsScrollViewIndicators: true,
                scrollViewBottomContentInset: dynamicTypeSize.isAccessibilitySize ? 260 : 180,
                contentSpacing: 36,
                contentPadding: .init(top: 40, leading: 8, bottom: 0, trailing: 8),
                featureListSpacing: 26,
                featureListPadding: .init(top: 0, leading: 0, bottom: 0, trailing: 0),
                featureImageWidth: 44,
                featureHorizontalSpacing: 16,
                featureHorizontalAlignment: .top,
                featureVerticalSpacing: 6,
                footerPrimaryActionButtonCornerRadius: 16
            )
        )
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("IntroductionBackground").ignoresSafeArea())
        .tint(Color("BrandBlue"))
    }

    private var releaseNotes: WhatsNew {
        WhatsNew(
            version: .init(stringLiteral: AppIntroduction.releaseVersion),
            title: .init(text: .init("Pocket Helper \(AppIntroduction.releaseVersion)\n新功能")),
            features: [
                .init(
                    image: .init {
                        Image("IntroductionIcon")
                            .resizable()
                            .frame(width: 44, height: 44)
                            .clipShape(.rect(cornerRadius: 10))
                    },
                    title: "照片、视频与 Live Photo",
                    subtitle: "视频转为 HEVC，照片转为 HEIF。支持 Live Photo，可分别调整压缩质量与动态部分分辨率。"
                ),
                .init(
                    image: .init(systemName: "camera.on.rectangle.fill", foregroundColor: Color("BrandBlue")),
                    title: "发现 DJI 相簿新素材",
                    subtitle: "完整照片授权后，检测 DJI Album 新素材；也能手动选择照片和视频，确认后开始转换。"
                ),
                .init(
                    image: .init(systemName: "list.bullet.rectangle.fill", foregroundColor: Color("BrandMediumBlue")),
                    title: "进度与结果，一目了然",
                    subtitle: "查看进度、暂停或继续队列，在「历史」查看结果。新副本保存在系统照片的 Pocket Helper 相簿。"
                ),
                .init(
                    image: .init(systemName: "checkmark.shield.fill", foregroundColor: Color("BrandLightBlue")),
                    title: "本机处理，原片由你决定",
                    subtitle: "App 不上传素材。新副本保存并通过校验后，仍需你确认才会删除原片。iCloud 原片可能由系统联网下载。"
                )
            ],
            primaryAction: .init(
                title: .init(isReplay ? "完成" : "开始使用"),
                backgroundColor: Color(red: 18 / 255, green: 91 / 255, blue: 239 / 255),
                onDismiss: onFinish
            ),
            secondaryAction: .init(
                title: "查看使用指南",
                foregroundColor: Color("BrandBlue"),
                action: .present { UsageGuideSheet() }
            )
        )
    }
}

private struct UsageGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AppIntroductionView(destination: .welcome, isReplay: true) { dismiss() }
    }
}
