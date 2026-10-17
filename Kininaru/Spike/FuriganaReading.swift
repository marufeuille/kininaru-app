import Foundation

struct FuriganaToken: Equatable, Codable {
    var surface: String
    var latin: String
    var hiragana: String
}

struct FuriganaSample: Equatable {
    var sentence: String
    var expectedHiragana: String
    var hint: String
}

enum FuriganaSamples {
    static let all: [FuriganaSample] = [
        FuriganaSample(
            sentence: "空はなぜ青いの",
            expectedHiragana: "そらわなぜあおいの",
            hint: "助詞の「は」は「わ」。空は「そら」。"
        ),
        FuriganaSample(
            sentence: "今日は学校へ行きます",
            expectedHiragana: "きょうわがっこうへいきます",
            hint: "今日は「きょう」。助詞の「は」は「わ」。"
        ),
        FuriganaSample(
            sentence: "私は日本に住んでいます",
            expectedHiragana: "わたしわにほんにすんでいます",
            hint: "私は「わたし」を期待する。わたくし、と出ることがある。"
        ),
        FuriganaSample(
            sentence: "人はなぜ夢を見るの",
            expectedHiragana: "ひとわなぜゆめをみるの",
            hint: "助詞の「は」は「わ」。"
        ),
    ]
}

enum FuriganaReading {
    /// `kCFStringTokenizerUnitWord` で切り、ラテン転写を平仮名にする。
    /// 日本語の転写はローマ字のことが多く、そのままではルビに使えない。
    static func tokenize(_ text: String) -> [FuriganaToken] {
        let ns = text as NSString
        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            text as CFString,
            CFRange(location: 0, length: ns.length),
            kCFStringTokenizerUnitWord,
            Locale(identifier: "ja_JP") as CFLocale
        )
        var tokens: [FuriganaToken] = []
        while true {
            let kind = CFStringTokenizerAdvanceToNextToken(tokenizer)
            if kind.rawValue == 0 { break }
            let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard tokenRange.location >= 0, tokenRange.length > 0 else { continue }
            let nsRange = NSRange(location: tokenRange.location, length: tokenRange.length)
            guard NSMaxRange(nsRange) <= ns.length else { continue }
            let surface = ns.substring(with: nsRange)
            let latin = copyLatin(tokenizer)
            tokens.append(
                FuriganaToken(
                    surface: surface,
                    latin: latin,
                    hiragana: hiragana(fromLatin: latin)
                )
            )
        }
        return tokens
    }

    static func hiragana(fromLatin latin: String) -> String {
        if latin.isEmpty { return "" }
        if latin.unicodeScalars.contains(where: isKana) {
            return latin
        }
        let mutable = NSMutableString(string: latin)
        let transformed = CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false)
        return transformed ? (mutable as String) : latin
    }

    static func compactReading(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    private static func copyLatin(_ tokenizer: CFStringTokenizer) -> String {
        let value = CFStringTokenizerCopyCurrentTokenAttribute(
            tokenizer,
            kCFStringTokenizerAttributeLatinTranscription
        )
        return (value as? String) ?? ""
    }

    private static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        (0x3040...0x30FF).contains(scalar.value)
    }
}

enum FuriganaQuality {
    static func notes(tokens: [FuriganaToken], sample: FuriganaSample) -> [String] {
        var notes: [String] = []
        let joined = FuriganaReading.compactReading(tokens.map(\.hiragana).joined())
        if joined != sample.expectedHiragana {
            let shown = joined.isEmpty ? "（空）" : joined
            notes.append("読みが期待と違う。得られた「\(shown)」期待「\(sample.expectedHiragana)」。\(sample.hint)")
        }
        for token in tokens where token.surface == "は" {
            let reading = token.hiragana.isEmpty ? token.latin : token.hiragana
            if reading != "わ" {
                notes.append("「は」の読みが「\(reading.isEmpty ? "（空）" : reading)」。助詞なら「わ」。")
            }
        }
        for token in tokens where token.surface == "今日" {
            if !token.hiragana.isEmpty && token.hiragana != "きょう" {
                notes.append("「今日」の読みが「\(token.hiragana)」。期待は「きょう」。")
            }
        }
        return notes
    }

    static let renderingLimit = "ルビは CTRubyAnnotation を UIView に描いている。SwiftUI の Text では出ない。行の上にはみ出す、文字とずれる、ことがある。数値にはしない。"
}
