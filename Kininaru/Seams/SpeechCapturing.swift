import Foundation

/// 音声入力の差し込み口。音声の追加スパイクのあとで、端末内認識に替える。
/// 許可を求めるメソッドは置いていない。質問画面のマイクは、それまで無効のまま。
protocol SpeechCapturing {
    var isConfigured: Bool { get }
}

struct UnconfiguredSpeechCapture: SpeechCapturing {
    var isConfigured: Bool { false }
}
