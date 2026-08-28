import SwiftUI

struct BannerView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @EnvironmentObject private var messageCenter: MessageCenter
    let message: BannerMessage

    var body: some View {
        Button {
            messageCenter.dismissBanner()
            messageCenter.isPresentingMessages = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: message.severity.symbol)
                    .foregroundStyle(message.severity == .error ? .red : .orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(message.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.ultraThinMaterial))
            .clipShape(.rect(cornerRadius: 18))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(message.severity.title)：\(message.title)。\(message.details)")
    }
}
