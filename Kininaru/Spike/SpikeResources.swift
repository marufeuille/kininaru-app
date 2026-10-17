import Foundation

enum SpikeResources {
    static func url(name: String, ext: String) -> URL? {
        let bundles = [Bundle.main, Bundle(for: BundleToken.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }
}

private final class BundleToken {}

enum SpeechSample {
    static let resourceName = "speech-sample"
    /// espeak-ng の ja 音声に読ませた文。認識結果がこれと違っても、計測は失敗にしない。
    static let script = "そらわなぜあおいの。たいようのひかりがくうきのなかでちらばるからです。"
}

enum AnswerSample {
    static let question = "空はなぜ青いの"
    static let resourceName = "source-excerpt"
    static let fallbackExcerpt = "太陽の光は、いろいろな色がまざっています。空気の中の小さなつぶに光があたると、青い光はほかの色よりたくさんちらばります。だから、空は青く見えます。"

    static func loadExcerpt() -> (text: String, source: String) {
        guard
            let url = SpikeResources.url(name: resourceName, ext: "txt"),
            let raw = try? String(contentsOf: url, encoding: .utf8)
        else {
            return (fallbackExcerpt, "fallback")
        }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return (fallbackExcerpt, "fallback")
        }
        return (text, "bundle")
    }
}
