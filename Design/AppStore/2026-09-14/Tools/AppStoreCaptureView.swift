#if DEBUG
import Photos
import SwiftData
import SwiftUI

/// Temporary capture navigation only: all screens and media descriptors are production views/data.
struct AppStoreCaptureView: View {
    let screen: String
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var coordinator: ProcessingCoordinator
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("转换", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") }.tag(0)
            HistoryView()
                .tabItem { Label("历史", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") }.tag(1)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }.tag(2)
        }
        .sheet(isPresented: $coordinator.showsInitialPreview) {
            InitialScanPreviewView().interactiveDismissDisabled()
        }
        .task {
            coordinator.configure(context: context)
            selectedTab = screen == "settings" ? 2 : 0
            if screen == "selection" {
                let assets = PHAsset.fetchAssets(with: nil)
                var identifiers: [String] = []
                assets.enumerateObjects { asset, _, _ in
                    let name = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
                    if name.hasPrefix("dji_export_") && asset.mediaType == .image {
                        identifiers.append(asset.localIdentifier)
                    }
                }
                coordinator.importPickedIdentifiers(identifiers)
            }
        }
    }
}
#endif
