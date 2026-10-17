import Foundation

struct HistoryItem: Equatable, Hashable, Identifiable, Sendable {
    var id: String
    var question: String
    var answerExcerpt: String
}

enum SampleHistory {
    static let items: [HistoryItem] = [
        HistoryItem(
            id: "sample-1",
            question: "空はなぜ青いの",
            answerExcerpt: "太陽の光が空気の中でちらばるからです。"
        ),
        HistoryItem(
            id: "sample-2",
            question: "月はなぜ光るの",
            answerExcerpt: "太陽の光をはね返しているからです。"
        ),
        HistoryItem(
            id: "sample-3",
            question: "雨はどうしてふるの",
            answerExcerpt: "雲の中の水が集まって落ちてくるからです。"
        ),
        HistoryItem(
            id: "sample-4",
            question: "なぜ季節があるの",
            answerExcerpt: "地球がかたむいたまま太陽のまわりを回るからです。"
        ),
    ]
}
