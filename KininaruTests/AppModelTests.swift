import XCTest
@testable import Kininaru

@MainActor
final class AppModelTests: XCTestCase {
    func testSearchRejectsEmptyAndWhitespace() {
        XCTAssertFalse(QuestionDraft.canSearch(""))
        XCTAssertFalse(QuestionDraft.canSearch("   \n\t"))
        XCTAssertFalse(QuestionDraft.canSearch("　"))
        XCTAssertTrue(QuestionDraft.canSearch("  空はなぜ青いの  "))
        XCTAssertEqual(QuestionDraft.normalized("  空はなぜ青いの \n"), "空はなぜ青いの")

        let model = AppModel()
        XCTAssertFalse(model.canSearch)
        model.draft = " \n "
        model.submitQuestion()
        XCTAssertTrue(model.path.isEmpty)

        model.draft = "　"
        XCTAssertFalse(model.canSearch)
    }

    func testSubmitTrimsQuestionAndUsesAnswerGenerator() {
        let model = AppModel(answers: FixedAnswerGenerator())
        model.draft = "  空はなぜ青いの \n"
        XCTAssertTrue(model.canSearch)
        model.submitQuestion()

        guard case .answer(let presentation) = model.path.last else {
            return XCTFail("答えへ進んでいない")
        }
        XCTAssertEqual(presentation.question, "空はなぜ青いの")
        XCTAssertEqual(presentation.body, "テストの答え")
    }

    func testNextQuestionClearsDraftFromHistory() {
        let model = AppModel()
        model.draft = "下書き"
        model.showHistory()
        model.openHistoryItem(model.historyItems[0])
        XCTAssertEqual(model.path.count, 2)

        model.askNextQuestion()
        XCTAssertEqual(model.draft, "")
        XCTAssertNil(model.microphoneNote)
        XCTAssertTrue(model.path.isEmpty)
        XCTAssertFalse(model.canSearch)
    }

    func testHistoryStoreIsSwappable() {
        let item = HistoryItem(id: "custom", question: "独自の質問", answerExcerpt: "独自の答え")
        let model = AppModel(history: FixedHistoryStore(items: [item]))
        XCTAssertEqual(model.historyItems, [item])

        model.showHistory()
        model.openHistoryItem(item)

        guard case .answer(let presentation) = model.path.last else {
            return XCTFail("履歴から答えへ進んでいない")
        }
        XCTAssertEqual(presentation.question, "独自の質問")
        XCTAssertEqual(presentation.body, "独自の答え")
    }

    func testMicrophoneDoesNotRequestPermission() {
        let model = AppModel()
        XCTAssertFalse(model.speech.isConfigured)
        XCTAssertEqual(model.microphoneAvailability, "まだ使えません")

        model.noteMicrophone()
        XCTAssertEqual(model.microphoneNote, "音声入力は、このあとで使えるようにします。")
        XCTAssertFalse(model.speech.isConfigured)
    }
}

private struct FixedAnswerGenerator: AnswerGenerating {
    func answer(for question: String, sources: [SourceDocument]) -> String {
        _ = question
        _ = sources
        return "テストの答え"
    }
}

private struct FixedHistoryStore: HistoryStoring {
    var items: [HistoryItem]
}
