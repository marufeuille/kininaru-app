import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var draft: String
    var path: [Route]
    var microphoneNote: String?

    let speech: any SpeechCapturing
    let sources: any SourceFetching
    let answers: any AnswerGenerating
    let history: any HistoryStoring

    init(
        draft: String = "",
        speech: any SpeechCapturing = UnconfiguredSpeechCapture(),
        sources: any SourceFetching = UnconfiguredSourceFetcher(),
        answers: any AnswerGenerating = PlaceholderAnswerGenerator(),
        history: any HistoryStoring = PlaceholderHistoryStore()
    ) {
        self.draft = draft
        self.path = []
        self.microphoneNote = nil
        self.speech = speech
        self.sources = sources
        self.answers = answers
        self.history = history
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
        let question = QuestionDraft.normalized(draft)
        guard QuestionDraft.canSearch(question) else { return }
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
        microphoneNote = nil
        path.removeAll()
    }

    func noteMicrophone() {
        microphoneNote = "音声入力は、このあとで使えるようにします。"
    }

    /// S3 で `sources.fetchSources` を呼ぶ場所。S0 は空のまま返し、通信しない。
    private func collectedSources() -> [SourceDocument] {
        _ = sources
        return []
    }
}
