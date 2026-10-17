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
        let usage = MemoryUsage()
        let model = AppModel(answers: FixedAnswerGenerator(), usage: usage)
        model.draft = "  空はなぜ青いの \n"
        XCTAssertTrue(model.canSearch)
        model.submitQuestion()

        guard case .answer(let presentation) = model.path.last else {
            return XCTFail("答えへ進んでいない")
        }
        XCTAssertEqual(presentation.question, "空はなぜ青いの")
        XCTAssertEqual(presentation.body, "テストの答え")
        XCTAssertEqual(model.usageCount, 1)
        XCTAssertEqual(usage.count, 1)
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

    func testMarkedTextStaysInTheSubmission() {
        XCTAssertEqual(
            QuestionDraft.visibleText(committed: "空は", marked: "なぜ"),
            "空はなぜ"
        )
        XCTAssertEqual(
            QuestionDraft.visibleText(committed: "空はなぜ", marked: "なぜ"),
            "空はなぜ"
        )
        XCTAssertEqual(
            QuestionDraft.submitText(
                visible: QuestionDraft.visibleText(committed: "", marked: "そら")
            ),
            "そら"
        )
        let visible = QuestionDraft.visibleText(committed: "月は", marked: "なんで")
        XCTAssertEqual(QuestionDraft.submitText(visible: visible), "月はなんで")
        XCTAssertNotEqual(QuestionDraft.submitText(visible: visible), "月は")
        XCTAssertNil(
            QuestionDraft.submitText(
                visible: QuestionDraft.visibleText(committed: " \n", marked: "　")
            )
        )
    }

    func testFieldSyncDoesNotOverwriteComposition() {
        XCTAssertNil(
            QuestionFieldSync.textToApply(current: "そら", isComposing: true, external: "")
        )
        XCTAssertNil(
            QuestionFieldSync.textToApply(current: "空", isComposing: false, external: "空")
        )
        XCTAssertEqual(
            QuestionFieldSync.textToApply(current: "空", isComposing: false, external: ""),
            ""
        )
    }

    func testSubmitWhileComposingUsesVisibleText() {
        let model = AppModel(usage: MemoryUsage())
        model.draft = QuestionDraft.visibleText(committed: "空は", marked: "なぜ")
        model.submitQuestion()

        guard case .answer(let presentation) = model.path.last else {
            return XCTFail("答えへ進んでいない")
        }
        XCTAssertEqual(presentation.question, "空はなぜ")
        XCTAssertEqual(model.usageCount, 1)
        XCTAssertFalse(model.speech.isConfigured)
    }

    func testUsageCountIncrementsAndNeverBlocks() {
        let usage = MemoryUsage()
        let model = AppModel(usage: usage)
        XCTAssertEqual(model.usageCount, 0)

        model.draft = "   \n　"
        model.submitQuestion()
        XCTAssertEqual(model.usageCount, 0)
        XCTAssertTrue(model.path.isEmpty)

        model.draft = "空はなぜ青いの"
        model.submitQuestion()
        XCTAssertEqual(model.usageCount, 1)

        usage.count = 50
        let again = AppModel(usage: usage)
        XCTAssertEqual(again.usageCount, 50)
        again.draft = "まだできる"
        XCTAssertTrue(again.canSearch)
        again.submitQuestion()
        XCTAssertEqual(again.usageCount, 51)
        XCTAssertEqual(usage.count, 51)
    }

    func testUsageCountStaysOnDeviceAndOmitsQuestionText() throws {
        let suite = "kininaru.usage.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let counter = DeviceUsageCounter(defaults: defaults, processArguments: [])
        let sources = SpySourceFetcher()
        let model = AppModel(sources: sources, usage: counter)
        model.draft = "  秘密の質問 \n"
        model.submitQuestion()

        XCTAssertEqual(sources.calls, 0)
        XCTAssertEqual(counter.count, 1)

        let domain = defaults.persistentDomain(forName: suite) ?? [:]
        XCTAssertEqual(domain.count, 1)
        XCTAssertEqual(domain[DeviceUsageCounter.storageKey] as? Int, 1)
        for value in domain.values {
            XCTAssertFalse(String(describing: value).contains("秘密の質問"))
        }

        let restored = AppModel(
            usage: DeviceUsageCounter(defaults: defaults, processArguments: [])
        )
        XCTAssertEqual(restored.usageCount, 1)

        let reset = DeviceUsageCounter(
            defaults: defaults,
            processArguments: [DeviceUsageCounter.resetArgument]
        )
        XCTAssertEqual(reset.count, 0)
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

private final class MemoryUsage: UsageCounting {
    var count: Int
    init(_ count: Int = 0) { self.count = count }
    func increment() { count += 1 }
}

private final class SpySourceFetcher: SourceFetching {
    var calls = 0
    func fetchSources(for searchTerms: String) async throws -> [SourceDocument] {
        calls += 1
        _ = searchTerms
        throw SourceFetchError.notConfigured
    }
}
