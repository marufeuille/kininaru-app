import Foundation

/// 履歴の差し込み口。S5 で端末内の保存に替える。iCloud 同期は付けない。
protocol HistoryStoring {
    var items: [HistoryItem] { get }
}

struct PlaceholderHistoryStore: HistoryStoring {
    var items: [HistoryItem] = SampleHistory.items
}
