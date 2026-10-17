import Foundation

enum SystemModelAvailabilitySnapshot: Equatable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case osTooOld
    case sdkMissing
    case other(String)
}

struct AvailabilityDecision: Equatable {
    var available: Bool
    var code: String
    var reason: String
}

enum AnswerAvailability {
    static func interpret(
        _ snapshot: SystemModelAvailabilitySnapshot,
        frameworkOnDisk: Bool
    ) -> AvailabilityDecision {
        switch snapshot {
        case .available:
            return AvailabilityDecision(
                available: true,
                code: "available",
                reason: "SystemLanguageModel が available。端末内で生成する。"
            )
        case .deviceNotEligible:
            return AvailabilityDecision(
                available: false,
                code: "deviceNotEligible",
                reason: "この端末は Apple Intelligence の対象外です（deviceNotEligible）。iPad (A16) はここに当たります。モデルは呼びません。"
            )
        case .appleIntelligenceNotEnabled:
            return AvailabilityDecision(
                available: false,
                code: "appleIntelligenceNotEnabled",
                reason: "Apple Intelligence がオフです（appleIntelligenceNotEnabled）。モデルは呼びません。"
            )
        case .modelNotReady:
            return AvailabilityDecision(
                available: false,
                code: "modelNotReady",
                reason: "モデルの準備ができていません（modelNotReady）。ダウンロードは始めません。モデルは呼びません。"
            )
        case .osTooOld:
            return AvailabilityDecision(
                available: false,
                code: "osTooOld",
                reason: "iPadOS 26 未満のため FoundationModels を実行できません（osTooOld）。"
            )
        case .sdkMissing:
            var reason = "このビルドの SDK に FoundationModels がありません（sdkMissing）。実行時の理由コードを取るには Xcode 26 以降で実機に入れてください。"
            if frameworkOnDisk {
                reason += " 端末にはフレームワークのファイルがありますが、このバイナリはリンクしていないので deviceNotEligible などは読めません。"
            }
            return AvailabilityDecision(available: false, code: "sdkMissing", reason: reason)
        case .other(let detail):
            let text = detail.isEmpty ? "未知の理由で利用できません。" : detail
            return AvailabilityDecision(available: false, code: "unavailableOther", reason: text)
        }
    }
}

enum FoundationModelsLocation {
    static func existsOnDisk() -> Bool {
        FileManager.default.fileExists(
            atPath: "/System/Library/Frameworks/FoundationModels.framework"
        )
    }
}

enum SystemModelAvailabilityReader {
    static func current() -> SystemModelAvailabilitySnapshot {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return FoundationModelsBridge.availability()
        }
        return .osTooOld
        #else
        return .sdkMissing
        #endif
    }
}

enum OnDeviceAlternatives {
    static let lines: [String] = [
        "FoundationModels の SystemLanguageModel は、iPadOS 26 以降の Apple Intelligence です。iPad では M1 以降と iPad mini（A17 Pro）が対象で、2025 年の無印 iPad (A16)（iPad15,7 / iPad15,8）は対象外です。Private Cloud Compute は通信するので使いません。",
        "NaturalLanguage（NLTagger、NLEmbedding、NLModel）は、分かち書き、品詞、埋め込み、分類までです。質問への文章は作れません。",
        "Core ML に生成モデルの重みを同梱すれば理論上は動かせます。重みは同梱していません。ダウンロードもしません。",
        "Writing Tools などの OS の生成機能も Apple Intelligence が要ります。A16 では出ません。",
        "第三者の SDK と、大きなモデルのダウンロードは入れていません。A16 で、標準 API だけで子ども向けの答えを端末内に組み立てる現実的な方法はありません。",
    ]
}

enum CompositionRubric {
    /// スパイク用の仮の線。体験の合格点ではない。
    static let onDeviceFirstSeconds = 15.0
    static let onDevicePeakBytes: UInt64 = 1_200_000_000
}

enum CompositionProposal {
    static func make(device: DeviceSnapshot, answer: ProbeSummary?) -> String {
        var prefix = ""
        if device.isSimulator {
            prefix = "これはシミュレータの結果です。数値は採用しません。実機の書き出しを使ってください。\n"
        }
        if device.isLikelyA16iPad {
            prefix += "識別子 \(device.modelIdentifier) は \(device.marketingName) です。\n"
        }
        guard let answer, answer.runCount > 0 else {
            return prefix + "まだ答えの組み立ては測っていません。iPad (A16)（iPad15,7 / iPad15,8）では、実行時の理由コードは deviceNotEligible になる見込みです。Xcode 26 以降で、iPadOS 26 以降の実機に入れて測ってください。"
        }
        let body: String
        switch answer.availabilityCode {
        case "deviceNotEligible":
            body = "D1 提案: 答えの組み立てはクラウドにする。FoundationModels の実行時理由は deviceNotEligible で、この端末では端末内の言語モデルを使えない。モデルは呼んでいない。音声認識、ふりがな、読み上げは端末内のままにする。クラウドにする場合でも、質問の原文を端末の外に出さない、という制約は別の設計が要る。"
        case "appleIntelligenceNotEnabled":
            body = "D1 提案: 理由コードは appleIntelligenceNotEnabled。対象の端末なら Apple Intelligence をオンにして測り直す。iPad (A16) は対象外なので、オフではなく deviceNotEligible になるはず。このコードのままなら、答えはクラウドにする。"
        case "modelNotReady":
            body = "D1 提案: 理由コードは modelNotReady。準備ができてから測り直す。アプリからダウンロードは始めない。準備できなければ答えはクラウドにする。"
        case "osTooOld":
            body = "D1 提案: 理由コードは osTooOld。iPadOS 26 以降で測り直す。iPad (A16) は上げても deviceNotEligible の見込みで、答えはクラウドにする。"
        case "sdkMissing":
            body = "D1 提案: 理由コードは sdkMissing。このビルドでは実行時の理由が取れていない。Xcode 26 以降で実機向けにビルドし直す。iPad (A16) の見込みは deviceNotEligible。その場合、答えはクラウドにする。"
        case "available":
            body = availableText(answer)
        case "generationFailed":
            body = "D1 提案: モデルは使える判定だったが、生成に失敗した（generationFailed）。詳細を見て、直せないなら答えはクラウドにする。"
        default:
            body = "D1 提案: 答えの計測が揃っていない（理由コード \(answer.availabilityCode)）。iPad (A16) の想定は deviceNotEligible で、その場合は答えをクラウドにする。"
        }
        return prefix + body
    }

    private static func availableText(_ answer: ProbeSummary) -> String {
        let seconds = answer.medianFirstSeconds ?? .infinity
        let peak = answer.medianMemoryPeakBytes ?? .max
        let withinTime = seconds <= CompositionRubric.onDeviceFirstSeconds
        let withinMemory = peak < CompositionRubric.onDevicePeakBytes
        if withinTime && withinMemory {
            return "D1 提案: この計測では FoundationModels が使えた。初回秒の中央値とピークは仮の線（15 秒、1.2GB）以内なので、端末内を第一候補にできる。iPad (A16) ではこの結果にならない想定なので、識別子が iPad15,7 か iPad15,8 でないか確認する。"
        }
        return "D1 提案: FoundationModels は使えるが、仮の線（初回の中央値 15 秒、ピーク 1.2GB）を超えている。待ちを許せないなら答えはクラウドにする。線はスパイク用の仮置き。"
    }
}

enum AnswerCompositionProbe {
    @MainActor
    static func measure(runIndex: Int) async -> ProbeRun {
        let before = MemoryFootprint.bytes()
        let snapshot = SystemModelAvailabilityReader.current()
        let onDisk = FoundationModelsLocation.existsOnDisk()
        let decision = AnswerAvailability.interpret(snapshot, frameworkOnDisk: onDisk)
        let excerpt = AnswerSample.loadExcerpt()
        var details: [String: String] = [
            "question": AnswerSample.question,
            "excerptSource": excerpt.source,
            "frameworkOnDisk": onDisk ? "true" : "false",
            "availabilityCode": decision.code,
        ]
        guard decision.available else {
            let after = MemoryFootprint.bytes()
            return ProbeRun.finished(
                probe: .answer,
                runIndex: runIndex,
                available: false,
                code: decision.code,
                reason: decision.reason,
                before: before,
                after: after,
                peak: max(before, after),
                notes: ["モデルは呼んでいない。通信もしない。"],
                details: details
            )
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await FoundationModelsBridge.measure(
                runIndex: runIndex,
                before: before,
                details: details
            )
        }
        #endif
        let after = MemoryFootprint.bytes()
        return ProbeRun.finished(
            probe: .answer,
            runIndex: runIndex,
            available: false,
            code: "osTooOld",
            reason: AnswerAvailability.interpret(.osTooOld, frameworkOnDisk: onDisk).reason,
            before: before,
            after: after,
            peak: max(before, after),
            notes: ["モデルは呼んでいない。"],
            details: details
        )
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
enum FoundationModelsBridge {
    static func availability() -> SystemModelAvailabilitySnapshot {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .deviceNotEligible
            case .appleIntelligenceNotEnabled:
                return .appleIntelligenceNotEnabled
            case .modelNotReady:
                return .modelNotReady
            @unknown default:
                return .other(String(describing: reason))
            }
        @unknown default:
            return .other("未知の availability")
        }
    }

    static func measure(
        runIndex: Int,
        before: UInt64,
        details: [String: String]
    ) async -> ProbeRun {
        var details = details
        let monitor = FootprintMonitor(start: before)
        monitor.start()
        let firstStart = Date()
        do {
            let firstText = try await generateOnce()
            let firstSeconds = WallClock.seconds(from: firstStart)
            let mid = MemoryFootprint.bytes()
            let warmStart = Date()
            let warmText = try await generateOnce()
            let warmSeconds = WallClock.seconds(from: warmStart)
            let after = MemoryFootprint.bytes()
            let peak = max(monitor.stop(), before, mid, after)
            details["model"] = "SystemLanguageModel.default"
            return ProbeRun.finished(
                probe: .answer,
                runIndex: runIndex,
                available: true,
                code: "available",
                reason: "固定の質問と同梱の抜粋だけで、端末内の SystemLanguageModel が答えを書いた。",
                first: firstSeconds,
                warm: warmSeconds,
                before: before,
                after: after,
                peak: peak,
                outputText: "初回:\n\(firstText)\n\nウォーム:\n\(warmText)",
                notes: ["通信はしていない。入力欄の質問は使っていない。"],
                details: details
            )
        } catch {
            let after = MemoryFootprint.bytes()
            let peak = max(monitor.stop(), before, after)
            details["error"] = String(describing: error)
            return ProbeRun.finished(
                probe: .answer,
                runIndex: runIndex,
                available: false,
                code: "generationFailed",
                reason: "生成に失敗した。\(error.localizedDescription)",
                before: before,
                after: after,
                peak: peak,
                notes: ["失敗後に通信へは切り替えない。"],
                details: details
            )
        }
    }

    private static func generateOnce() async throws -> String {
        let session = LanguageModelSession(instructions: {
            "あなたは子どもの質問に答える人です。"
            "むずかしい言葉を使わず、2文から4文の短い日本語で答えてください。"
            "渡された文章だけを使い、文章に無いことは書かないでください。"
        })
        let question = AnswerSample.question
        let excerpt = AnswerSample.loadExcerpt().text
        let response = try await session.respond(to: Prompt {
            "質問: \(question)"
            "参考にする文章:"
            "\(excerpt)"
            "この文章だけを使って、子どもにわかる短い答えを書いてください。"
        })
        return response.content
    }
}
#endif
