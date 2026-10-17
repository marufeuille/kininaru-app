import Foundation

enum FuriganaProbe {
    @MainActor
    static func measure(runIndex: Int) -> ProbeRun {
        let before = MemoryFootprint.bytes()
        let monitor = FootprintMonitor(start: before)
        monitor.start()
        let firstStart = Date()
        let first = FuriganaSamples.all.map { sample in
            (sample, FuriganaReading.tokenize(sample.sentence))
        }
        let firstSeconds = WallClock.seconds(from: firstStart)
        let mid = MemoryFootprint.bytes()
        let warmStart = Date()
        let warm = FuriganaSamples.all.map { FuriganaReading.tokenize($0.sentence) }
        let warmSeconds = WallClock.seconds(from: warmStart)
        let after = MemoryFootprint.bytes()
        let peak = max(monitor.stop(), before, mid, after)

        let tokenCount = first.reduce(0) { $0 + $1.1.count }
        var notes = [FuriganaQuality.renderingLimit]
        var output: [String] = []
        if tokenCount == 0 {
            return ProbeRun.finished(
                probe: .furigana,
                runIndex: runIndex,
                available: false,
                code: "tokenizerFailed",
                reason: "CFStringTokenizer がトークンを返さなかった。",
                first: firstSeconds,
                warm: warmSeconds,
                before: before,
                after: after,
                peak: peak,
                notes: notes
            )
        }
        for (sample, tokens) in first {
            let reading = tokens.map(\.hiragana).joined()
            output.append(sample.sentence)
            output.append("読み: \(reading)")
            output.append("期待: \(sample.expectedHiragana)")
            let quality = FuriganaQuality.notes(tokens: tokens, sample: sample)
            if quality.isEmpty {
                output.append("期待と一致。")
            } else {
                quality.forEach { output.append($0) }
                notes.append(contentsOf: quality.map { "\(sample.sentence): \($0)" })
            }
            output.append("")
        }
        _ = warm
        return ProbeRun.finished(
            probe: .furigana,
            runIndex: runIndex,
            available: true,
            code: "available",
            reason: "CFStringTokenizer で読みを取った。誤読は出力に残している。正しさは保証しない。",
            first: firstSeconds,
            warm: warmSeconds,
            before: before,
            after: after,
            peak: peak,
            outputText: output.joined(separator: "\n"),
            notes: notes,
            details: [
                "tokenizerUnit": "kCFStringTokenizerUnitWord",
                "locale": "ja_JP",
                "tokenCount": String(tokenCount),
            ]
        )
    }
}
