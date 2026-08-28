import SwiftData
import SwiftUI

struct MessageCenterView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case errors = "错误"
        case warnings = "警告"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: ProcessingCoordinator
    @Query(sort: \AppMessage.createdAt, order: .reverse) private var messages: [AppMessage]
    @State private var filter: Filter = .all

    private var filteredMessages: [AppMessage] {
        switch filter {
        case .all: messages
        case .errors: messages.filter { $0.severity == .error }
        case .warnings: messages.filter { $0.severity == .warning }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("筛选", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                if filteredMessages.isEmpty {
                    ContentUnavailableView("没有消息", systemImage: "bell.slash")
                        .frame(maxHeight: .infinity)
                } else {
                    List(filteredMessages) { message in
                        MessageRow(message: message) {
                            perform(message.action, jobIdentifier: message.jobIdentifier)
                        }
                        .onAppear { message.isRead = true }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("消息中心")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !messages.isEmpty {
                        Button("清除", role: .destructive) {
                            messages.forEach(modelContext.delete)
                            try? modelContext.save()
                        }
                    }
                }
            }
        }
        .onDisappear { try? modelContext.save() }
    }

    private func perform(_ action: MessageAction, jobIdentifier: String?) {
        switch action {
        case .retry, .retryDownload:
            if let jobIdentifier { coordinator.retry(jobIdentifier: jobIdentifier) }
            dismiss()
        case .openSettings:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        case .none:
            break
        }
    }
}

private struct MessageRow: View {
    let message: AppMessage
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: message.severity.symbol)
                    .foregroundStyle(message.severity == .error ? .red : .orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(message.title).font(.headline)
                        if !message.isRead {
                            Circle().fill(.tint).frame(width: 7, height: 7)
                        }
                    }
                    Text("\(message.stage) · \(AppFormatters.date.string(from: message.createdAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(message.details)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let errorCode = message.errorCode {
                Text(errorCode)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            if message.action != .none {
                Button(message.action == .openSettings ? "打开设置" : "重新处理", action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
    }
}
