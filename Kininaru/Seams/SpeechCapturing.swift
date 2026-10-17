import Foundation

/// 音声入力の差し込み口。S2 で Speech framework の端末内認識に替える。
/// 許可を求めるメソッドは置いていない。S0 からは呼べない。
protocol SpeechCapturing {
    var isConfigured: Bool { get }
}

struct UnconfiguredSpeechCapture: SpeechCapturing {
    var isConfigured: Bool { false }
}
