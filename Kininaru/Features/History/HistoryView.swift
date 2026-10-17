import SwiftUI

struct HistoryView: View {
    var model: AppModel

    var body: some View {
        List(model.historyItems) { item in
            Button {
                model.openHistoryItem(item)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.question)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(item.answerExcerpt)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("history-\(item.id)")
        }
        .listStyle(.insetGrouped)
        .navigationTitle("履歴")
        .navigationBarTitleDisplayMode(.inline)
    }
}
