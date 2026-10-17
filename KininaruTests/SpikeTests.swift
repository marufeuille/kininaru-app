import AVFoundation
import Speech
import UIKit
import XCTest
@testable import Kininaru

final class SpikeReportTests: XCTestCase {
    func testMedianPicksMiddleAndAveragesEvenCounts() {
        XCTAssertNil(SpikeStats.median([]))
        XCTAssertEqual(SpikeStats.median([2]), 2)
        XCTAssertEqual(SpikeStats.median([10, 30, 20]), 20)
        XCTAssertEqual(SpikeStats.median([1, 2, 3, 4]), 2.5)
        let mebibytes = [100, 300, 200].map { UInt64($0) * 1024 * 1024 }
        XCTAssertEqual(SpikeStats.medianBytes(mebibytes), UInt64(200) * 1024 * 1024)
        XCTAssertEqual(SpikeStats.medianBytes([1_000, 3_000]), UInt64(2_000))
    }

    func testMarkdownTableUsesMedianAndDeviceNotEligible() throws {
        let report = SpikeReport.make(
            device: device(identifier: "iPad15,7", simulator: false),
            runs: answerRuns(code: "deviceNotEligible", available: false),
            createdAt: Date(timeIntervalSince1970: 1_760_720_000)
        )
        let markdown = SpikeReportMarkdown.render(report)
        let summary = try XCTUnwrap(report.summaries.first)
        XCTAssertEqual(summary.title, "答えの組み立て")
        XCTAssertFalse(summary.available)
        XCTAssertEqual(summary.availabilityCode, "deviceNotEligible")
        XCTAssertEqual(summary.medianFirstSeconds, 20)
        XCTAssertEqual(summary.medianWarmSeconds, 5)
        let twoHundredMebibytes = UInt64(200) * 1024 * 1024
        XCTAssertEqual(summary.medianMemoryAfterBytes, twoHundredMebibytes)
        XCTAssertEqual(summary.medianMemoryPeakBytes, twoHundredMebibytes)
        XCTAssertEqual(SpikeReportMarkdown.seconds(20), "20.000")
        XCTAssertEqual(SpikeReportMarkdown.seconds(5), "5.000")
        XCTAssertEqual(SpikeReportMarkdown.seconds(2.5), "2.500")
        XCTAssertEqual(SpikeReportMarkdown.mebibytes(twoHundredMebibytes), "200.0")
        XCTAssertEqual(SpikeReportMarkdown.mebibytes(nil), "—")
        XCTAssertTrue(markdown.contains("| プローブ | 可否 | 理由コード | 初回秒 | ウォーム秒 | 終了時MiB | ピークMiB |"))
        let row = "| 答えの組み立て | 不可 | deviceNotEligible | 20.000 | 5.000 | 200.0 | 200.0 |"
        XCTAssertTrue(markdown.contains(row), markdown)
        XCTAssertTrue(markdown.contains("iPad15,7"))
        XCTAssertTrue(markdown.contains("実機"))
        XCTAssertTrue(markdown.contains("phys_footprint"))
        XCTAssertTrue(markdown.contains("requiresOnDeviceRecognition"))
        XCTAssertFalse(markdown.contains("http://"))
        XCTAssertFalse(markdown.contains("https://"))

        let decoded = try SpikeReportJSON.decode(SpikeReportJSON.data(report))
        XCTAssertEqual(decoded.summaries.first?.availabilityCode, "deviceNotEligible")
        XCTAssertEqual(decoded.runs.first?.outputText, "まだ生成していない")
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    func testMarkdownEscapesPipesInCells() {
        XCTAssertEqual(SpikeReportMarkdown.cell("a|b\nc"), "a\\|b c")
    }

    func testMixedAvailabilityCodesStayVisible() {
        var runs = answerRuns(code: "deviceNotEligible", available: false)
        runs[1].availabilityCode = "generationFailed"
        runs[1].reason = "生成に失敗した"
        let summaries = SpikeReport.summarize(runs)
        XCTAssertEqual(summaries.first?.availabilityCode, "mixed")
        XCTAssertEqual(summaries.first?.available, false)
        XCTAssertTrue(summaries.first?.reason.contains("deviceNotEligible") == true)
        XCTAssertTrue(summaries.first?.reason.contains("generationFailed") == true)
    }

    func testPhysicalFootprintReadsTaskVMInfo() {
        XCTAssertGreaterThan(MemoryFootprint.bytes(), 0)
    }

    @MainActor
    func testCurrentDeviceMatchesSimulatorEnvironment() {
        let device = DeviceSnapshot.current()
        let expected = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] != nil
        XCTAssertEqual(device.isSimulator, expected)
        XCTAssertFalse(device.systemVersion.isEmpty)
        XCTAssertFalse(device.modelIdentifier.isEmpty)
    }

    func testA16Identifiers() {
        XCTAssertEqual(DeviceIdentity.marketingName(for: "iPad15,7"), "iPad (A16) Wi-Fi（2025）")
        XCTAssertEqual(
            DeviceIdentity.marketingName(for: "iPad15,8"),
            "iPad (A16) Wi-Fi + Cellular（2025）"
        )
        XCTAssertTrue(DeviceIdentity.isA16iPad("iPad15,7"))
        XCTAssertFalse(DeviceIdentity.isA16iPad("iPad16,3"))
    }

    func testBundledSpikeResources() throws {
        let speech = try XCTUnwrap(SpikeResources.url(name: SpeechSample.resourceName, ext: "wav"))
        let excerpt = try XCTUnwrap(SpikeResources.url(name: AnswerSample.resourceName, ext: "txt"))
        let audio = try AVAudioFile(forReading: speech)
        let seconds = Double(audio.length) / audio.fileFormat.sampleRate
        XCTAssertGreaterThan(seconds, 2)
        XCTAssertEqual(audio.fileFormat.channelCount, 1)
        let text = try String(contentsOf: excerpt, encoding: .utf8)
        XCTAssertTrue(text.contains("青"))
        XCTAssertFalse(text.lowercased().contains("http"))
        let loaded = AnswerSample.loadExcerpt()
        XCTAssertEqual(loaded.source, "bundle")
        XCTAssertFalse(loaded.text.contains("http"))
    }

    private func answerRuns(code: String, available: Bool) -> [ProbeRun] {
        let peaks: [UInt64] = [100, 300, 200].map { $0 * 1024 * 1024 }
        let first: [Double] = [10, 30, 20]
        let warm: [Double] = [4, 6, 5]
        return (0..<3).map { index in
            ProbeRun.finished(
                probe: .answer,
                runIndex: index + 1,
                available: available,
                code: code,
                reason: "理由 \(code)",
                first: first[index],
                warm: warm[index],
                before: peaks[index],
                after: peaks[index],
                peak: peaks[index],
                outputText: index == 0 ? "まだ生成していない" : nil
            )
        }
    }

    private func device(identifier: String, simulator: Bool) -> DeviceSnapshot {
        DeviceSnapshot(
            modelIdentifier: identifier,
            marketingName: DeviceIdentity.marketingName(for: identifier),
            hardwareMachine: identifier,
            systemName: "iPadOS",
            systemVersion: "26.0",
            operatingSystemVersionString: "Version 26.0",
            isSimulator: simulator,
            isLikelyA16iPad: DeviceIdentity.isA16iPad(identifier)
        )
    }
}

final class ProbeAvailabilityTests: XCTestCase {
    func testSpeechDoesNotRunWhenOnDeviceIsUnsupported() {
        let decision = SpeechOnDevicePolicy.fileAvailability(
            recognizerCreated: true,
            supportsOnDevice: false,
            recognizerAvailable: true,
            audioFileExists: true,
            authorization: .authorized
        )
        XCTAssertFalse(decision.available)
        XCTAssertFalse(decision.mayRunOnDevice)
        XCTAssertEqual(decision.code, "onDeviceUnsupported")
    }

    func testSpeechFileHappyPathMayRunOnDeviceOnly() {
        let decision = SpeechOnDevicePolicy.fileAvailability(
            recognizerCreated: true,
            supportsOnDevice: true,
            recognizerAvailable: true,
            audioFileExists: true,
            authorization: .authorized
        )
        XCTAssertTrue(decision.mayRunOnDevice)
        XCTAssertEqual(decision.code, "available")
    }

    func testSpeechFileMissingAudioDoesNotRun() {
        let decision = SpeechOnDevicePolicy.fileAvailability(
            recognizerCreated: true,
            supportsOnDevice: true,
            recognizerAvailable: true,
            audioFileExists: false,
            authorization: .authorized
        )
        XCTAssertEqual(decision.code, "audioMissing")
        XCTAssertFalse(decision.mayRunOnDevice)
    }

    func testSpeechDeniedDoesNotRun() {
        let decision = SpeechOnDevicePolicy.micAvailability(
            recognizerCreated: true,
            supportsOnDevice: true,
            recognizerAvailable: true,
            authorization: .denied,
            microphoneGranted: true
        )
        XCTAssertEqual(decision.code, "speechNotAuthorized")
        XCTAssertFalse(decision.mayRunOnDevice)
    }

    func testMicrophoneDeniedDoesNotRun() {
        let decision = SpeechOnDevicePolicy.micAvailability(
            recognizerCreated: true,
            supportsOnDevice: true,
            recognizerAvailable: true,
            authorization: .authorized,
            microphoneGranted: false
        )
        XCTAssertEqual(decision.code, "microphoneNotAuthorized")
        XCTAssertFalse(decision.mayRunOnDevice)
    }

    func testRequestRequiresOnDeviceRecognition() {
        let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: "/tmp/kininaru-unused.caf"))
        SpeechRequestConfiguration.applyOnDeviceOnly(request)
        XCTAssertTrue(request.requiresOnDeviceRecognition)
    }

    func testVoicePolicyUsesOnlyDefaultJapanese() {
        let voices = [
            ListedVoice(identifier: "premium", language: "ja-JP", quality: "premium"),
            ListedVoice(identifier: "enhanced", language: "ja-JP", quality: "enhanced"),
            ListedVoice(identifier: "kyoko", language: "ja-JP", quality: "default"),
            ListedVoice(identifier: "en", language: "en-US", quality: "default"),
        ]
        XCTAssertEqual(JapaneseVoicePolicy.synthesisChoice(from: voices)?.identifier, "kyoko")
        let premiumOnly = voices.filter { $0.quality != "default" }
        XCTAssertNil(JapaneseVoicePolicy.synthesisChoice(from: premiumOnly))
    }

    func testFoundationModelsReasonsAreExplicit() {
        let cases: [(SystemModelAvailabilitySnapshot, String, Bool)] = [
            (.available, "available", true),
            (.deviceNotEligible, "deviceNotEligible", false),
            (.appleIntelligenceNotEnabled, "appleIntelligenceNotEnabled", false),
            (.modelNotReady, "modelNotReady", false),
            (.osTooOld, "osTooOld", false),
            (.sdkMissing, "sdkMissing", false),
            (.other("custom"), "unavailableOther", false),
        ]
        for item in cases {
            let decision = AnswerAvailability.interpret(item.0, frameworkOnDisk: false)
            XCTAssertEqual(decision.code, item.1)
            XCTAssertEqual(decision.available, item.2)
        }
        let onDisk = AnswerAvailability.interpret(.sdkMissing, frameworkOnDisk: true)
        XCTAssertTrue(onDisk.reason.contains("リンクしていない"))
        XCTAssertTrue(onDisk.reason.contains("Xcode 26"))
        let ineligible = AnswerAvailability.interpret(.deviceNotEligible, frameworkOnDisk: true)
        XCTAssertTrue(ineligible.reason.contains("deviceNotEligible"))
        XCTAssertTrue(ineligible.reason.contains("呼びません"))
    }

    func testProposalForA16IsCloud() {
        let device = DeviceSnapshot(
            modelIdentifier: "iPad15,7",
            marketingName: DeviceIdentity.marketingName(for: "iPad15,7"),
            hardwareMachine: "iPad15,7",
            systemName: "iPadOS",
            systemVersion: "26.0",
            operatingSystemVersionString: "Version 26.0",
            isSimulator: false,
            isLikelyA16iPad: true
        )
        let summary = ProbeSummary(
            probe: "answer",
            title: "答えの組み立て",
            available: false,
            availabilityCode: "deviceNotEligible",
            reason: "対象外",
            runCount: 3,
            medianFirstSeconds: nil,
            medianWarmSeconds: nil,
            medianMemoryAfterBytes: nil,
            medianMemoryPeakBytes: nil
        )
        let text = CompositionProposal.make(device: device, answer: summary)
        XCTAssertTrue(text.contains("クラウド"))
        XCTAssertTrue(text.contains("deviceNotEligible"))
        XCTAssertTrue(text.contains("iPad15,7"))
        XCTAssertFalse(text.contains("http"))
    }

    func testProposalWhenSdkIsMissingAsksForXcode26() {
        let device = DeviceSnapshot(
            modelIdentifier: "arm64",
            marketingName: "対応表に無い端末（arm64）",
            hardwareMachine: "arm64",
            systemName: "iPadOS",
            systemVersion: "18.5",
            operatingSystemVersionString: "Version 18.5",
            isSimulator: true,
            isLikelyA16iPad: false
        )
        let summary = ProbeSummary(
            probe: "answer",
            title: "答えの組み立て",
            available: false,
            availabilityCode: "sdkMissing",
            reason: "SDK が無い",
            runCount: 1,
            medianFirstSeconds: nil,
            medianWarmSeconds: nil,
            medianMemoryAfterBytes: nil,
            medianMemoryPeakBytes: nil
        )
        let text = CompositionProposal.make(device: device, answer: summary)
        XCTAssertTrue(text.contains("シミュレータ"))
        XCTAssertTrue(text.contains("sdkMissing"))
        XCTAssertTrue(text.contains("Xcode 26"))
        XCTAssertTrue(text.contains("クラウド"))
    }

    func testProposalWhenModelIsFastEnoughPrefersOnDevice() {
        let device = DeviceSnapshot(
            modelIdentifier: "iPad14,5",
            marketingName: "対応表に無い端末（iPad14,5）",
            hardwareMachine: "iPad14,5",
            systemName: "iPadOS",
            systemVersion: "26.0",
            operatingSystemVersionString: "Version 26.0",
            isSimulator: false,
            isLikelyA16iPad: false
        )
        let fast = ProbeSummary(
            probe: "answer",
            title: "答えの組み立て",
            available: true,
            availabilityCode: "available",
            reason: "使えた",
            runCount: 3,
            medianFirstSeconds: 3,
            medianWarmSeconds: 1,
            medianMemoryAfterBytes: 100_000_000,
            medianMemoryPeakBytes: 100_000_000
        )
        XCTAssertTrue(CompositionProposal.make(device: device, answer: fast).contains("端末内"))
        var slow = fast
        slow.medianFirstSeconds = 40
        XCTAssertTrue(CompositionProposal.make(device: device, answer: slow).contains("クラウド"))
    }

    func testUnmeasuredProposalNamesDeviceNotEligible() {
        let device = DeviceSnapshot(
            modelIdentifier: "iPad15,8",
            marketingName: DeviceIdentity.marketingName(for: "iPad15,8"),
            hardwareMachine: "iPad15,8",
            systemName: "iPadOS",
            systemVersion: "26.0",
            operatingSystemVersionString: "Version 26.0",
            isSimulator: false,
            isLikelyA16iPad: true
        )
        let text = CompositionProposal.make(device: device, answer: nil)
        XCTAssertTrue(text.contains("deviceNotEligible"))
        XCTAssertTrue(text.contains("まだ答えの組み立ては測っていません"))
        XCTAssertTrue(OnDeviceAlternatives.lines.contains { $0.contains("NaturalLanguage") })
        XCTAssertTrue(OnDeviceAlternatives.lines.contains { $0.contains("Core ML") })
        XCTAssertTrue(OnDeviceAlternatives.lines.contains { $0.contains("第三者") })
    }

    func testParticleHaIsFlagged() {
        let tokens = [
            FuriganaToken(surface: "空", latin: "sora", hiragana: "そら"),
            FuriganaToken(surface: "は", latin: "ha", hiragana: "は"),
        ]
        let sample = FuriganaSample(
            sentence: "空は",
            expectedHiragana: "そらわ",
            hint: "助詞の「は」は「わ」。"
        )
        let notes = FuriganaQuality.notes(tokens: tokens, sample: sample)
        XCTAssertTrue(notes.contains { $0.contains("は") && $0.contains("わ") })
    }

    func testKyouReadingIsFlagged() {
        let tokens = [FuriganaToken(surface: "今日", latin: "konnichi", hiragana: "こんにち")]
        let sample = FuriganaSample(sentence: "今日", expectedHiragana: "きょう", hint: "今日")
        let notes = FuriganaQuality.notes(tokens: tokens, sample: sample)
        XCTAssertTrue(notes.contains { $0.contains("きょう") })
    }

    func testLatinHiraganaConvertsRomaji() {
        let text = FuriganaReading.hiragana(fromLatin: "sora")
        XCTAssertTrue(text.contains("そ"), text)
    }

    func testTokenizerReturnsJapaneseSurfaces() {
        let sentence = "空はなぜ青いの"
        let tokens = FuriganaReading.tokenize(sentence)
        XCTAssertFalse(tokens.isEmpty)
        for token in tokens {
            XCTAssertFalse(token.surface.isEmpty)
            XCTAssertTrue(sentence.contains(token.surface))
        }
    }

    func testRubyStringKeepsSurfaces() {
        let tokens = [
            FuriganaToken(surface: "空", latin: "sora", hiragana: "そら"),
            FuriganaToken(surface: "は", latin: "ha", hiragana: "は"),
        ]
        let text = RubyAttributedString.make(tokens: tokens, baseColor: .label)
        XCTAssertEqual(text.string, "空は")
    }
}
