import SwiftUI

/// Keep startup scans and their sheets out of the introduction's presentation lifecycle.
struct AppEntryView: View {
    @AppStorage(AppIntroduction.completedGuideKey) private var hasCompletedGuide = false
    @AppStorage(AppIntroduction.seenReleaseKey) private var lastSeenRelease = ""

    var body: some View {
        if let destination = IntroductionDestination.automatic(
            hasCompletedGuide: hasCompletedGuide,
            lastSeenRelease: lastSeenRelease,
            currentRelease: AppIntroduction.releaseVersion
        ) {
            AppIntroductionView(destination: destination) {
                lastSeenRelease = AppIntroduction.releaseVersion
                hasCompletedGuide = true
            }
        } else {
            ContentView()
        }
    }
}

struct AppIntroductionView: View {
    let destination: IntroductionDestination
    var isReplay = false
    let onFinish: () -> Void

    var body: some View {
        switch destination {
        case .welcome:
            WelcomeGuideView(isReplay: isReplay, onFinish: onFinish)
        case .whatsNew:
            AppReleaseNotesView(isReplay: isReplay, onFinish: onFinish)
        }
    }
}

private struct WelcomeGuideView: View {
    var isReplay = false
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var page = 0
    @AccessibilityFocusState private var headingFocused: Bool

    private var isLastPage: Bool { page == 2 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    guideHeader
                    guideContent
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .id(page)
            .background(Color("IntroductionBackground").ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .navigationTitle(AppIdentity.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isReplay ? "关闭" : "直接开始", action: onFinish)
                        .accessibilityIdentifier("introduction.skip")
                }
            }
        }
        .tint(Color("BrandBlue"))
    }

    private var guideHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            if page == 0 {
                Image("IntroductionIcon")
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(.rect(cornerRadius: 22))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: page == 1 ? "slider.horizontal.3" : "checkmark.shield.fill")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(Color("BrandBlue"))
                    .frame(width: 72, height: 72)
                    .background(.blue.opacity(0.09), in: .rect(cornerRadius: 24))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text([AppIdentity.displayName, "简单三步，开始转换", "每一份原片，由你决定"][page])
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color("BrandBlue"))
                Text(["让回忆更轻。\n给精彩留点空间。", "从选择素材，\n到存好新副本。", "安心处理，\n放心保留。"][page])
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)
                    .accessibilityIdentifier("introduction.heading")
                Text([
                    "在 iPhone 和 iPad 上压缩照片、视频与 Live Photo，为下一次拍摄腾出空间。",
                    "先选好质量，再挑选素材。转换进度与处理结果，都可以在 App 里查看。",
                    "转换结果单独保存。确认满意后，再决定是否删除原片。"
                ][page])
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var guideContent: some View {
        switch page {
        case 0:
            card {
                feature("视频转为 HEVC", detail: "按需要选择节省空间、均衡或高质量。", symbol: "video.fill", color: Color("BrandBlue"))
                Divider()
                feature("照片转为 HEIF", detail: "压缩静态照片，也支持 Live Photo 的照片与动态部分。", symbol: "livephoto", color: Color("BrandMediumBlue"))
                Divider()
                feature("更方便地整理 DJI 素材", detail: "检测 DJI Album 新素材，也可手动选取照片和视频。", symbol: "photo.stack.fill", color: Color("BrandLightBlue"))
            }
        case 1:
            card {
                feature("01  先设置质量", detail: "在「设置」调整视频、照片质量和文件名。初次使用可先保留默认值。", symbol: "slider.horizontal.3", color: Color("BrandBlue"))
                Divider()
                feature("02  选择并开始转换", detail: "在「转换」授权访问照片，点「选择素材」或「扫描」，确认列表后开始转换。默认不会自动转换。", symbol: "photo.badge.plus", color: Color("BrandMediumBlue"))
                Divider()
                feature("03  查看保存结果", detail: "到系统照片的「\(PhotoLibraryService.albumName)」相簿查看新副本，在「历史」查看处理结果与节省空间。", symbol: "checkmark.circle.fill", color: Color("BrandLightBlue"))
            }
            note("自动检测需要完整照片访问权限；选择有限访问时，可手动选取已授权的素材。", symbol: "photo.badge.checkmark")
        default:
            card {
                feature("媒体在本机转换", detail: "App 不会上传你的素材。iCloud 中的原片可能由系统联网下载。", symbol: "iphone", color: Color("BrandBlue"))
                Divider()
                feature("保存、校验，再确认", detail: "新副本保存并通过校验后才会提供删除原片的选项；删除还需要你的确认和系统确认。", symbol: "checkmark.shield.fill", color: Color("BrandLightBlue"))
                Divider()
                feature("让转换顺利完成", detail: "iOS 26 及以上可由系统安排持续后台处理；更早版本请保持 App 在前台。", symbol: "clock.arrow.circlepath", color: Color("BrandMediumBlue"))
            }
            note("4K 60/120 fps 为实验性转换，开始前会再次提示，结果取决于设备能力。建议先用少量素材确认效果。", symbol: "info.circle")
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label("阅读隐私政策", systemImage: "hand.raised")
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 44)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Group {
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Capsule()
                            .fill(index == page ? Color("BrandBlue") : Color.secondary.opacity(0.25))
                            .frame(width: index == page ? 24 : 8, height: 6)
                    }
                    Text("\(page + 1) / 3")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("使用指南，第 \(page + 1) 页，共 3 页")
            }

            footerLayout {
                if page > 0 {
                    Button("上一步") { changePage(by: -1) }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 48)
                }
                Button {
                    if !isLastPage { changePage(by: 1) }
                    else { onFinish() }
                } label: {
                    Text(!isLastPage ? "继续了解" : (isReplay ? "完成" : "开始使用"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .accessibilityIdentifier("introduction.continue")
            }
            Text("随时可在「设置」重新查看")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color("IntroductionBackground"))
    }

    private var footerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    private func changePage(by amount: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            page += amount
        }
        headingFocused = true
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
    }

    private func feature(_ title: String, detail: String, symbol: String, color: Color) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return layout {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.10), in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func note(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("欢迎") {
    AppIntroductionView(destination: .welcome, onFinish: {})
}

#Preview("What’s New") {
    AppIntroductionView(destination: .whatsNew, onFinish: {})
}
