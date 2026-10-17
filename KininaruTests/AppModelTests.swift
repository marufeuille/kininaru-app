import UIKit
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

    func testSpeechStaysUnconfigured() {
        let model = AppModel(usage: MemoryUsage())
        XCTAssertFalse(model.speech.isConfigured)
        XCTAssertEqual(model.microphoneAvailability, "まだ使えません")
        model.draft = "空はなぜ青いの"
        model.submitQuestion()
        XCTAssertFalse(model.speech.isConfigured)
    }

    func testFieldTextIncludesMarkedComposition() {
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 240, height: 44))
        field.setMarkedText("そら", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertNotNil(field.markedTextRange)
        XCTAssertEqual(field.text, "そら")
        XCTAssertEqual(QuestionDraft.submitText(visible: field.text ?? ""), "そら")

        // つぎの質問で空にするときは、変換中でも欄を消す。消さないと前の文字が残る。
        XCTAssertEqual(
            QuestionFieldSync.textToApply(current: field.text ?? "", isComposing: true, external: ""),
            ""
        )
        field.text = ""
        XCTAssertNil(field.markedTextRange)
        XCTAssertEqual(field.text ?? "", "")
    }

    func testEndEditingDoesNotRestoreClearedDraft() {
        XCTAssertEqual(
            QuestionFieldSync.textAfterEndEditing(draft: "", fieldText: "そら"),
            ""
        )
        XCTAssertEqual(
            QuestionFieldSync.textAfterEndEditing(draft: "そら", fieldText: "そら"),
            "そら"
        )
        XCTAssertNil(
            QuestionFieldSync.textToApply(current: "そら", isComposing: true, external: "空")
        )
        XCTAssertNil(
            QuestionFieldSync.textToApply(current: "空", isComposing: false, external: "空")
        )
        XCTAssertEqual(
            QuestionFieldSync.textToApply(current: "空", isComposing: false, external: ""),
            ""
        )
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
