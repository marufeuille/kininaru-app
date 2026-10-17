import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var draft: String
    var path: [Route]

    /// 調べた回数。質問画面に出す。回数では止めない。
    private(set) var usageCount: Int

    let speech: any SpeechCapturing
    let sources: any SourceFetching
    let answers: any AnswerGenerating
    let history: any HistoryStoring
    private let usage: any UsageCounting

    init(
        draft: String = "",
        speech: any SpeechCapturing = UnconfiguredSpeechCapture(),
        sources: any SourceFetching = UnconfiguredSourceFetcher(),
        answers: any AnswerGenerating = PlaceholderAnswerGenerator(),
        history: any HistoryStoring = PlaceholderHistoryStore(),
        usage: any UsageCounting = DeviceUsageCounter()
    ) {
        self.draft = draft
        self.path = []
        self.speech = speech
        self.sources = sources
        self.answers = answers
        self.history = history
        self.usage = usage
        self.usageCount = usage.count
    }

    var canSearch: Bool {
        QuestionDraft.canSearch(draft)
    }

    var historyItems: [HistoryItem] {
        history.items
    }

    var microphoneAvailability: String {
        speech.isConfigured ? "準備できています" : "まだ使えません"
    }

    func submitQuestion() {
        guard let question = QuestionDraft.submitText(visible: draft) else { return }
        usage.increment()
        usageCount = usage.count
        // 答えの仮実装には質問を渡す。通信はしない。原文を外に出さない作りは検索語づくりと S3 で行う。
        let body = answers.answer(for: question, sources: collectedSources())
        path.append(.answer(AnswerPresentation(question: question, body: body)))
    }

    func showHistory() {
        path.append(.history)
    }

    func openHistoryItem(_ item: HistoryItem) {
        let presentation = AnswerPresentation(
            question: item.question,
            body: item.answerExcerpt
        )
        path.append(.answer(presentation))
    }

    func askNextQuestion() {
        draft = ""
        path.removeAll()
    }

    /// S3 で `sources.fetchSources` を呼ぶ場所。S0 は空のまま返し、通信しない。
    private func collectedSources() -> [SourceDocument] {
        _ = sources
        return []
    }
}
