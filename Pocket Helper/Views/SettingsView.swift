import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var coordinator: ProcessingCoordinator
    @State private var showsResetDetectionConfirmation = false
    @State private var introduction: IntroductionDestination?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("视频质量", selection: $settings.videoQuality) {
                        ForEach(VideoQuality.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("照片质量", selection: $settings.photoQuality) {
                        ForEach(PhotoQuality.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Live Photo 动态部分", selection: $settings.liveResolution) {
                        ForEach(LiveMotionResolution.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("压缩质量")
                } footer: {
                    Text("均衡档基准：4K30 为 16 Mbps、1080P30 为 6 Mbps、720P30 为 2 Mbps；60 fps 提高 50%，120 fps 提高 100%。节省空间档为基准的 80%，高质量档为 125%。4K60/120 转换前会要求实验性确认。")
                }

                Section("文件名") {
                    Picker("命名规则", selection: $settings.filenameRule) {
                        ForEach(FilenameRule.allCases) { Text($0.title).tag($0) }
                    }
                    switch settings.filenameRule {
                    case .originalWithSuffix:
                        TextField("后缀", text: $settings.filenameSuffix)
                            .textInputAutocapitalization(.never)
                    case .automaticCounter:
                        LabeledContent("下一编号", value: String(format: "PH_%06d", settings.automaticCounter))
                    case .customTemplate:
                        TextField("模板", text: $settings.filenameTemplate)
                            .textInputAutocapitalization(.never)
                        Text("可用：{original}、{date}、{time}、{counter}、{media}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("预览", value: filenamePreview)
                        .lineLimit(1)
                }

                Section {
                    Toggle("保存后提示删除原片", isOn: $settings.deleteOriginals)
                } header: {
                    Text("原片")
                } footer: {
                    Text("\(AppIdentity.displayName) 不会静默删除。完成后需要先在 App 中确认，再通过 PhotoKit 的系统确认。")
                }

                Section {
                    Picker("自动检测", selection: $settings.autoDetectionScope) {
                        ForEach(AutoDetectionScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    Toggle("扫描后自动转换", isOn: $settings.autoConvert)
                    Button {
                        showsResetDetectionConfirmation = true
                    } label: {
                        Label("重置检测最近 7 天", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(coordinator.isScanning || coordinator.isProcessing)
                    .popover(
                        isPresented: $showsResetDetectionConfirmation,
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .bottom
                    ) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("重新检测最近 7 天？")
                                .font(.headline)
                            Text("只检查 DJI Album 中没有处理记录的\(settings.autoDetectionScope.title)；照片选项包含普通照片和 Live Photo。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button("取消", role: .cancel) {
                                    showsResetDetectionConfirmation = false
                                }
                                Spacer()
                                Button("开始检测") {
                                    showsResetDetectionConfirmation = false
                                    Task { await coordinator.resetDetectionAndScanRecentWeek() }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(20)
                        .frame(idealWidth: 320)
                        .presentationCompactAdaptation(.popover)
                    }
                } header: {
                    Text("检测范围")
                } footer: {
                    Text("照片包含普通照片和 Live Photo。首次检测从当天零点开始，之后只检测上次检测后新增的素材；开启自动转换后，新发现的 DJI 素材会直接加入处理队列。重置检测临时扩大到最近 7 天。")
                }

                Section {
                    Label("媒体仅在本机处理", systemImage: "lock.shield")
                    if #available(iOS 26.0, *) {
                        LabeledContent {
                            Text("支持")
                                .foregroundStyle(.green)
                        } label: {
                            Label("后台处理", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        }
                    } else {
                        LabeledContent {
                            Text("不支持")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("后台处理", systemImage: "iphone")
                        }
                    }
                } header: {
                    Text("隐私与后台")
                } footer: {
                    Text("持续后台转换需要 iOS 26 或更高版本；iOS 18–25 仍可在 App 前台完成转换。")
                }

                Section("关于") {
                    LabeledContent("版本", value: "\(AppIntroduction.installedVersion) (\(AppIntroduction.installedBuild))")
                    Button {
                        introduction = .welcome
                    } label: {
                        Label("使用指南", systemImage: "book.closed")
                    }
                    Button {
                        introduction = .whatsNew
                    } label: {
                        Label("What’s New · 版本亮点", systemImage: "sparkles")
                    }
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("隐私政策", systemImage: "hand.raised")
                    }
                }
            }
            .navigationTitle("设置")
            .sheet(item: $introduction) { destination in
                AppIntroductionView(destination: destination, isReplay: true) {
                    introduction = nil
                }
            }
        }
    }

    private var filenamePreview: String {
        let stem = FilenameGenerator.stem(
            originalFilename: "DJI_0001.MP4",
            kind: .video,
            rule: settings.filenameRule,
            suffix: settings.filenameSuffix,
            template: settings.filenameTemplate,
            counter: settings.automaticCounter,
            date: .now
        )
        return "\(stem).mov"
    }
}
