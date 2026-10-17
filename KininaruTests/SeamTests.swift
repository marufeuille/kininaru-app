import XCTest
@testable import Kininaru

final class SeamTests: XCTestCase {
    func testPlaceholderAnswerIgnoresSources() {
        let generator = PlaceholderAnswerGenerator()
        let text = generator.answer(for: "空はなぜ青いの", sources: [])
        XCTAssertEqual(text, PlaceholderAnswerGenerator.text)
    }

    func testSampleHistoryHasQuestionAndExcerpt() {
        XCTAssertEqual(SampleHistory.items.count, 4)
        for item in SampleHistory.items {
            XCTAssertFalse(item.id.isEmpty)
            XCTAssertFalse(item.question.isEmpty)
            XCTAssertFalse(item.answerExcerpt.isEmpty)
        }
    }

    func testSpeechCaptureStartsUnconfigured() {
        XCTAssertFalse(UnconfiguredSpeechCapture().isConfigured)
    }

    func testSourceFetcherDoesNotRun() async {
        let fetcher = UnconfiguredSourceFetcher()
        do {
            _ = try await fetcher.fetchSources(for: "空")
            XCTFail("出典取得が動いてしまった")
        } catch SourceFetchError.notConfigured {
            return
        } catch {
            XCTFail("想定外のエラー \(error)")
        }
    }
}
