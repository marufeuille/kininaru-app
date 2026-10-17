import Foundation

enum SpikePlan {
    static let runsPerProbe = 3
}

enum ProbeKind: String, Codable, CaseIterable {
    case furigana
    case tts
    case speechFile
    case speechMic
    case answer

    var title: String {
        switch self {
        case .furigana: "ふりがな"
        case .tts: "読み上げ"
        case .speechFile: "音声認識（ファイル）"
        case .speechMic: "音声認識（マイク）"
        case .answer: "答えの組み立て"
        }
    }
}

struct ProbeRun: Codable, Equatable, Identifiable {
    var id: String
    var probe: ProbeKind
    var runIndex: Int
    var available: Bool
    var availabilityCode: String
    var reason: String
    var firstElapsedSeconds: Double?
    var warmElapsedSeconds: Double?
    var memoryBeforeBytes: UInt64?
    var memoryAfterBytes: UInt64?
    var memoryPeakBytes: UInt64?
    var outputText: String?
    var notes: [String]
    var details: [String: String]

    static func finished(
        probe: ProbeKind,
        runIndex: Int,
        available: Bool,
        code: String,
        reason: String,
        first: Double? = nil,
        warm: Double? = nil,
        before: UInt64? = nil,
        after: UInt64? = nil,
        peak: UInt64? = nil,
        outputText: String? = nil,
        notes: [String] = [],
        details: [String: String] = [:]
    ) -> ProbeRun {
        ProbeRun(
            id: "\(probe.rawValue)#\(runIndex)",
            probe: probe,
            runIndex: runIndex,
            available: available,
            availabilityCode: code,
            reason: reason,
            firstElapsedSeconds: first,
            warmElapsedSeconds: warm,
            memoryBeforeBytes: before,
            memoryAfterBytes: after,
            memoryPeakBytes: peak,
            outputText: outputText,
            notes: notes,
            details: details
        )
    }
}

struct ProbeSummary: Codable, Equatable {
    var probe: String
    var title: String
    var available: Bool
    var availabilityCode: String
    var reason: String
    var runCount: Int
    var medianFirstSeconds: Double?
    var medianWarmSeconds: Double?
    var medianMemoryAfterBytes: UInt64?
    var medianMemoryPeakBytes: UInt64?
}

struct SpikeReport: Codable, Equatable {
    var schemaVersion: Int
    var createdAt: Date
    var device: DeviceSnapshot
    var summaries: [ProbeSummary]
    var runs: [ProbeRun]
    var proposal: String
    var onDeviceAlternatives: [String]
    var methodNote: String

    static func make(device: DeviceSnapshot, runs: [ProbeRun], createdAt: Date) -> SpikeReport {
        let summaries = summarize(runs)
        let answer = summaries.first { $0.probe == ProbeKind.answer.rawValue }
        return SpikeReport(
            schemaVersion: 1,
            createdAt: createdAt,
            device: device,
            summaries: summaries,
            runs: runs,
            proposal: CompositionProposal.make(device: device, answer: answer),
            onDeviceAlternatives: OnDeviceAlternatives.lines,
            methodNote: SpikeMethod.note
        )
    }

    static func summarize(_ runs: [ProbeRun]) -> [ProbeSummary] {
        var order: [ProbeKind] = []
        for run in runs where !order.contains(run.probe) {
            order.append(run.probe)
        }
        return order.map { kind in
            let group = runs.filter { $0.probe == kind }
            let codes = Set(group.map(\.availabilityCode))
            let code = codes.count == 1 ? (codes.first ?? "unknown") : "mixed"
            let reason: String
            if codes.count == 1 {
                reason = group.first?.reason ?? ""
            } else {
                reason = "回ごとに理由が違う: \(codes.sorted().joined(separator: ", "))"
            }
            return ProbeSummary(
                probe: kind.rawValue,
                title: kind.title,
                available: !group.isEmpty && group.allSatisfy(\.available),
                availabilityCode: code,
                reason: reason,
                runCount: group.count,
                medianFirstSeconds: SpikeStats.median(group.compactMap(\.firstElapsedSeconds)),
                medianWarmSeconds: SpikeStats.median(group.compactMap(\.warmElapsedSeconds)),
                medianMemoryAfterBytes: SpikeStats.medianBytes(group.compactMap(\.memoryAfterBytes)),
                medianMemoryPeakBytes: SpikeStats.medianBytes(group.compactMap(\.memoryPeakBytes))
            )
        }
    }
}

enum SpikeStats {
    static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    static func medianBytes(_ values: [UInt64]) -> UInt64? {
        // `map(Double.init)` は Double(bitPattern:) を選び、バイト数が 0 付近になる。
        median(values.map { Double($0) }).map { UInt64($0.rounded()) }
    }
}

enum SpikeMethod {
    static let note = """
    秒数は Date の壁時計の差で、CPU 時間ではない。各回は初回と、直後のウォーム。表の初回秒・ウォーム秒は、プローブごとの中央値（3 回なら 2 番目。偶数なら中央 2 つの平均）。読み上げの秒数は、最初の PCM バッファまで。合計時間は詳細の firstTotalSeconds と warmTotalSeconds。メモリは task_vm_info の phys_footprint（バイト）。MiB は 1024×1024 で割った値。ピークはその回の初回とウォームを通した最大。音声認識は requiresOnDeviceRecognition = true だけで、サーバ認識には落とさない。アプリから通信はしない。質問は固定の見本だけで、入力欄の文は送らない。
    """
}

enum SpikeReportJSON {
    static func data(_ report: SpikeReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    static func string(_ report: SpikeReport) throws -> String {
        String(decoding: try data(report), as: UTF8.self)
    }

    static func decode(_ data: Data) throws -> SpikeReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SpikeReport.self, from: data)
    }
}

enum SpikeReportMarkdown {
    static func render(_ report: SpikeReport) -> String {
        var lines: [String] = []
        lines.append("# きになる S1 計測")
        lines.append("")
        lines.append(deviceSection(report))
        lines.append("")
        lines.append(SpikeMethod.note.replacingOccurrences(of: "\n", with: " "))
        lines.append("")
        lines.append("## 中央値")
        lines.append("")
        lines.append("| プローブ | 可否 | 理由コード | 初回秒 | ウォーム秒 | 終了時MiB | ピークMiB |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- |")
        if report.summaries.isEmpty {
            lines.append("| — | — | — | — | — | — | — |")
        }
        for summary in report.summaries {
            lines.append(
                "| \(cell(summary.title)) | \(summary.available ? "可" : "不可") | \(cell(summary.availabilityCode)) | \(seconds(summary.medianFirstSeconds)) | \(seconds(summary.medianWarmSeconds)) | \(mebibytes(summary.medianMemoryAfterBytes)) | \(mebibytes(summary.medianMemoryPeakBytes)) |"
            )
        }
        lines.append("")
        lines.append("## 各回")
        lines.append("")
        lines.append("| プローブ | 回 | 可否 | 理由コード | 初回秒 | ウォーム秒 | 前MiB | 後MiB | ピークMiB | 理由 |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
        for run in report.runs {
            lines.append(
                "| \(cell(run.probe.title)) | \(run.runIndex) | \(run.available ? "可" : "不可") | \(cell(run.availabilityCode)) | \(seconds(run.firstElapsedSeconds)) | \(seconds(run.warmElapsedSeconds)) | \(mebibytes(run.memoryBeforeBytes)) | \(mebibytes(run.memoryAfterBytes)) | \(mebibytes(run.memoryPeakBytes)) | \(cell(run.reason)) |"
            )
        }
        lines.append("")
        lines.append("## 出力とメモ")
        lines.append("")
        if report.runs.isEmpty {
            lines.append("まだ計測していない。")
            lines.append("")
        }
        for run in report.runs {
            lines.append("### \(run.probe.title) \(run.runIndex) 回目")
            lines.append("")
            lines.append(run.reason)
            lines.append("")
            if let output = run.outputText, !output.isEmpty {
                lines.append(output)
                lines.append("")
            }
            for note in run.notes where !note.isEmpty {
                lines.append("- \(note)")
            }
            let detailKeys = run.details.keys.sorted()
            for key in detailKeys {
                lines.append("- \(key): \(run.details[key] ?? "")")
            }
            lines.append("")
        }
        lines.append("## 答えの組み立て場所")
        lines.append("")
        lines.append(report.proposal)
        lines.append("")
        lines.append("## 端末内の代替")
        lines.append("")
        for line in report.onDeviceAlternatives {
            lines.append("- \(line)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func deviceSection(_ report: SpikeReport) -> String {
        let environment = report.device.isSimulator ? "シミュレータ（数値は採用しない）" : "実機"
        let a16 = report.device.isLikelyA16iPad ? "はい" : "いいえ"
        return """
        - 計測開始: \(iso8601(report.createdAt))
        - 機種識別子: \(report.device.modelIdentifier)
        - 機種: \(report.device.marketingName)
        - uname: \(report.device.hardwareMachine)
        - OS: \(report.device.systemName) \(report.device.systemVersion)
        - OS 詳細: \(report.device.operatingSystemVersionString)
        - 実行環境: \(environment)
        - iPad (A16) の識別子か: \(a16)
        """
    }

    static func cell(_ text: String) -> String {
        text
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    static func seconds(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return fixed(value, fractionDigits: 3)
    }

    static func mebibytes(_ bytes: UInt64?) -> String {
        guard let bytes else { return "—" }
        let value = Double(bytes) / 1024.0 / 1024.0
        guard value.isFinite else { return "—" }
        return fixed(value, fractionDigits: 1)
    }

    /// `String(format:locale:)` はロケール引数で桁がずれることがある。
    /// 書き出しは常に ASCII の小数点と、指定した桁数にする。
    static func fixed(_ value: Double, fractionDigits: Int) -> String {
        let digits = max(0, min(fractionDigits, 8))
        let sign = value < 0 ? "-" : ""
        let magnitude = abs(value)
        var scale = 1.0
        for _ in 0..<digits {
            scale *= 10
        }
        let scaled = (magnitude * scale).rounded(.toNearestOrAwayFromZero)
        guard scaled.isFinite, scaled <= Double(Int.max) else { return "—" }
        let scaleInt = max(Int(scale.rounded()), 1)
        let scaledInt = Int(scaled)
        let whole = scaledInt / scaleInt
        let fraction = scaledInt % scaleInt
        guard digits > 0 else { return "\(sign)\(whole)" }
        var fractionText = String(fraction)
        if fractionText.count < digits {
            fractionText = String(repeating: "0", count: digits - fractionText.count) + fractionText
        }
        return "\(sign)\(whole).\(fractionText)"
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

enum SpikeExport {
    static func write(_ report: SpikeReport) throws -> (markdown: URL, json: URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("kininaru-spike", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let markdownURL = folder.appendingPathComponent("kininaru-s1.md")
        let jsonURL = folder.appendingPathComponent("kininaru-s1.json")
        try SpikeReportMarkdown.render(report).write(to: markdownURL, atomically: true, encoding: .utf8)
        try SpikeReportJSON.data(report).write(to: jsonURL, options: .atomic)
        return (markdownURL, jsonURL)
    }
}
