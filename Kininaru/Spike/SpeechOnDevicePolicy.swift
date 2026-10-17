import Foundation

enum SpeechAuthState: Equatable {
    case authorized
    case denied
    case restricted
    case notDetermined
}

struct SpeechRunDecision: Equatable {
    var available: Bool
    var code: String
    var reason: String
    /// true のときだけ認識を始める。始めるリクエストは必ず requiresOnDeviceRecognition を true にする。
    var mayRunOnDevice: Bool
}

enum SpeechOnDevicePolicy {
    static func fileAvailability(
        recognizerCreated: Bool,
        supportsOnDevice: Bool,
        recognizerAvailable: Bool,
        audioFileExists: Bool,
        authorization: SpeechAuthState
    ) -> SpeechRunDecision {
        if let blocked = commonBlock(
            recognizerCreated: recognizerCreated,
            supportsOnDevice: supportsOnDevice,
            recognizerAvailable: recognizerAvailable,
            authorization: authorization
        ) {
            return blocked
        }
        if !audioFileExists {
            return SpeechRunDecision(
                available: false,
                code: "audioMissing",
                reason: "同梱の speech-sample.wav が無い。サーバ認識には切り替えない。",
                mayRunOnDevice: false
            )
        }
        return ready
    }

    static func micAvailability(
        recognizerCreated: Bool,
        supportsOnDevice: Bool,
        recognizerAvailable: Bool,
        authorization: SpeechAuthState,
        microphoneGranted: Bool
    ) -> SpeechRunDecision {
        if let blocked = commonBlock(
            recognizerCreated: recognizerCreated,
            supportsOnDevice: supportsOnDevice,
            recognizerAvailable: recognizerAvailable,
            authorization: authorization
        ) {
            return blocked
        }
        if !microphoneGranted {
            return SpeechRunDecision(
                available: false,
                code: "microphoneNotAuthorized",
                reason: "マイクが許可されていない。サーバ認識には切り替えない。",
                mayRunOnDevice: false
            )
        }
        return ready
    }

    private static func commonBlock(
        recognizerCreated: Bool,
        supportsOnDevice: Bool,
        recognizerAvailable: Bool,
        authorization: SpeechAuthState
    ) -> SpeechRunDecision? {
        if !recognizerCreated {
            return SpeechRunDecision(
                available: false,
                code: "recognizerUnavailable",
                reason: "ja-JP の SFSpeechRecognizer を作れない。",
                mayRunOnDevice: false
            )
        }
        if !supportsOnDevice {
            return SpeechRunDecision(
                available: false,
                code: "onDeviceUnsupported",
                reason: "supportsOnDeviceRecognition が false。サーバ認識は使わない。",
                mayRunOnDevice: false
            )
        }
        switch authorization {
        case .denied:
            return SpeechRunDecision(
                available: false,
                code: "speechNotAuthorized",
                reason: "音声認識が拒否されている。",
                mayRunOnDevice: false
            )
        case .restricted:
            return SpeechRunDecision(
                available: false,
                code: "speechNotAuthorized",
                reason: "音声認識が制限されている。",
                mayRunOnDevice: false
            )
        case .notDetermined:
            return SpeechRunDecision(
                available: false,
                code: "speechNotAuthorized",
                reason: "音声認識の許可がまだ決まっていない。",
                mayRunOnDevice: false
            )
        case .authorized:
            break
        }
        if !recognizerAvailable {
            return SpeechRunDecision(
                available: false,
                code: "recognizerUnavailable",
                reason: "SFSpeechRecognizer.isAvailable が false。サーバには落とさない。",
                mayRunOnDevice: false
            )
        }
        return nil
    }

    private static let ready = SpeechRunDecision(
        available: true,
        code: "available",
        reason: "端末内認識だけを実行する。",
        mayRunOnDevice: true
    )
}

struct ListedVoice: Equatable {
    var identifier: String
    var language: String
    var quality: String
}

enum JapaneseVoicePolicy {
    /// enhanced と premium は、未ダウンロードだと取得の通信が起き得る。合成には default だけを使う。
    static func synthesisChoice(from voices: [ListedVoice]) -> ListedVoice? {
        voices.first { $0.language.hasPrefix("ja") && $0.quality == "default" }
    }
}
