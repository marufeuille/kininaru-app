#if DEBUG
import AVFoundation
import Foundation
import Speech

enum SpeechRequestConfiguration {
    static func applyOnDeviceOnly(_ request: SFSpeechRecognitionRequest) {
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
    }
}

enum SpeechAuthorization {
    static func currentOrRequest() async -> SpeechAuthState {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined {
            return map(current)
        }
        let requested = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        return map(requested)
    }

    private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> SpeechAuthState {
        switch status {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }
}

enum MicrophoneAuthorization {
    static func currentOrRequest() async -> Bool {
        let application = AVAudioApplication.shared
        switch application.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return false
        }
    }
}

struct RecognitionOutcome: Equatable {
    var transcript: String
    var finished: Bool
    var error: String?
    var firstPartialSeconds: Double?
    var totalSeconds: Double
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func resumeOnce(_ body: () -> Void) {
        lock.lock()
        let shouldRun = !done
        if shouldRun { done = true }
        lock.unlock()
        if shouldRun { body() }
    }
}

private final class TranscriptBox: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    private var firstPartial: Double?

    func update(_ text: String, at seconds: Double) {
        lock.lock()
        if firstPartial == nil, !text.isEmpty {
            firstPartial = seconds
        }
        self.text = text
        lock.unlock()
    }

    func snapshot() -> (String, Double?) {
        lock.lock()
        defer { lock.unlock() }
        return (text, firstPartial)
    }
}

private final class RecognitionBox: @unchecked Sendable {
    var task: SFSpeechRecognitionTask?
    var worker: Task<Void, Never>?
    let gate = ResumeGate()
    let transcript = TranscriptBox()
    let started = Date()
}

enum OnDeviceRecognition {
    static func recognize(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechRecognitionRequest,
        timeoutNanoseconds: UInt64,
        beforeTimeout: (() async -> Void)? = nil
    ) async -> RecognitionOutcome {
        let box = RecognitionBox()
        let outcome: RecognitionOutcome = await withCheckedContinuation { continuation in
            box.task = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    box.transcript.update(
                        result.bestTranscription.formattedString,
                        at: WallClock.seconds(from: box.started)
                    )
                    if result.isFinal {
                        let snapshot = box.transcript.snapshot()
                        box.finish(
                            RecognitionOutcome(
                                transcript: snapshot.0,
                                finished: true,
                                error: nil,
                                firstPartialSeconds: snapshot.1,
                                totalSeconds: WallClock.seconds(from: box.started)
                            ),
                            continuation: continuation
                        )
                    }
                    return
                }
                if let error {
                    let snapshot = box.transcript.snapshot()
                    box.finish(
                        RecognitionOutcome(
                            transcript: snapshot.0,
                            finished: false,
                            error: error.localizedDescription,
                            firstPartialSeconds: snapshot.1,
                            totalSeconds: WallClock.seconds(from: box.started)
                        ),
                        continuation: continuation
                    )
                }
            }
            box.worker = Task {
                if let beforeTimeout {
                    await beforeTimeout()
                }
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                if Task.isCancelled { return }
                box.task?.cancel()
                let snapshot = box.transcript.snapshot()
                box.finish(
                    RecognitionOutcome(
                        transcript: snapshot.0,
                        finished: false,
                        error: "時間内に終わらなかった",
                        firstPartialSeconds: snapshot.1,
                        totalSeconds: WallClock.seconds(from: box.started)
                    ),
                    continuation: continuation
                )
            }
        }
        box.task?.cancel()
        box.worker?.cancel()
        return outcome
    }
}

private extension RecognitionBox {
    func finish(
        _ outcome: RecognitionOutcome,
        continuation: CheckedContinuation<RecognitionOutcome, Never>
    ) {
        gate.resumeOnce {
            task?.cancel()
            worker?.cancel()
            continuation.resume(returning: outcome)
        }
    }
}

enum SpeechFileProbe {
    @MainActor
    static func measure(runIndex: Int) async -> ProbeRun {
        let locale = Locale(identifier: "ja-JP")
        let recognizer = SFSpeechRecognizer(locale: locale)
        let supportsOnDevice = recognizer?.supportsOnDeviceRecognition ?? false
        let audioURL = SpikeResources.url(name: SpeechSample.resourceName, ext: "wav")
        let authorization = await SpeechAuthorization.currentOrRequest()
        let decision = SpeechOnDevicePolicy.fileAvailability(
            recognizerCreated: recognizer != nil,
            supportsOnDevice: supportsOnDevice,
            recognizerAvailable: recognizer?.isAvailable ?? false,
            audioFileExists: audioURL != nil,
            authorization: authorization
        )
        var details = baseDetails(
            supportsOnDevice: supportsOnDevice,
            mayRun: decision.mayRunOnDevice,
            authorization: authorization
        )
        details["audioFile"] = "\(SpeechSample.resourceName).wav"
        details["script"] = SpeechSample.script
        if let audioURL, let described = audioDescription(audioURL) {
            details.merge(described) { _, new in new }
        }
        guard decision.mayRunOnDevice, let recognizer, let audioURL else {
            let bytes = MemoryFootprint.bytes()
            return ProbeRun.finished(
                probe: .speechFile,
                runIndex: runIndex,
                available: false,
                code: decision.code,
                reason: decision.reason,
                before: bytes,
                after: bytes,
                peak: bytes,
                notes: ["認識は開始していない。"],
                details: details
            )
        }

        let before = MemoryFootprint.bytes()
        let monitor = FootprintMonitor(start: before)
        monitor.start()
        let first = await recognizeFile(url: audioURL, recognizer: recognizer)
        let mid = MemoryFootprint.bytes()
        let warm = await recognizeFile(url: audioURL, recognizer: recognizer)
        let after = MemoryFootprint.bytes()
        let peak = max(monitor.stop(), before, mid, after)
        let interpreted = interpret(first: first, warm: warm, fallbackReason: decision.reason)
        details["requiresOnDeviceRecognition"] = "true"
        if let partial = first.firstPartialSeconds {
            details["firstPartialSeconds"] = String(partial)
        }
        if let partial = warm.firstPartialSeconds {
            details["warmPartialSeconds"] = String(partial)
        }
        return ProbeRun.finished(
            probe: .speechFile,
            runIndex: runIndex,
            available: interpreted.available,
            code: interpreted.code,
            reason: interpreted.reason,
            first: first.totalSeconds,
            warm: warm.totalSeconds,
            before: before,
            after: after,
            peak: peak,
            outputText: interpreted.output,
            notes: interpreted.notes,
            details: details
        )
    }

    @MainActor
    private static func recognizeFile(url: URL, recognizer: SFSpeechRecognizer) async -> RecognitionOutcome {
        let request = SFSpeechURLRecognitionRequest(url: url)
        SpeechRequestConfiguration.applyOnDeviceOnly(request)
        guard request.requiresOnDeviceRecognition else {
            return RecognitionOutcome(
                transcript: "",
                finished: false,
                error: "requiresOnDeviceRecognition を true にできなかった",
                firstPartialSeconds: nil,
                totalSeconds: 0
            )
        }
        return await OnDeviceRecognition.recognize(
            recognizer: recognizer,
            request: request,
            timeoutNanoseconds: 25_000_000_000
        )
    }
}

enum SpeechMicProbe {
    @MainActor
    static func measure(runIndex: Int) async -> ProbeRun {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
        let supportsOnDevice = recognizer?.supportsOnDeviceRecognition ?? false
        let authorization = await SpeechAuthorization.currentOrRequest()
        let microphoneGranted = await MicrophoneAuthorization.currentOrRequest()
        let decision = SpeechOnDevicePolicy.micAvailability(
            recognizerCreated: recognizer != nil,
            supportsOnDevice: supportsOnDevice,
            recognizerAvailable: recognizer?.isAvailable ?? false,
            authorization: authorization,
            microphoneGranted: microphoneGranted
        )
        var details = baseDetails(
            supportsOnDevice: supportsOnDevice,
            mayRun: decision.mayRunOnDevice,
            authorization: authorization
        )
        details["microphoneGranted"] = microphoneGranted ? "true" : "false"
        details["listenSeconds"] = "4"
        guard decision.mayRunOnDevice, let recognizer else {
            let bytes = MemoryFootprint.bytes()
            return ProbeRun.finished(
                probe: .speechMic,
                runIndex: runIndex,
                available: false,
                code: decision.code,
                reason: decision.reason,
                before: bytes,
                after: bytes,
                peak: bytes,
                notes: ["マイク認識は開始していない。"],
                details: details
            )
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        SpeechRequestConfiguration.applyOnDeviceOnly(request)
        guard request.requiresOnDeviceRecognition else {
            let bytes = MemoryFootprint.bytes()
            return ProbeRun.finished(
                probe: .speechMic,
                runIndex: runIndex,
                available: false,
                code: "refusedServerRecognition",
                reason: "requiresOnDeviceRecognition を true にできなかった。",
                before: bytes,
                after: bytes,
                peak: bytes,
                details: details
            )
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
        } catch {
            let bytes = MemoryFootprint.bytes()
            return ProbeRun.finished(
                probe: .speechMic,
                runIndex: runIndex,
                available: false,
                code: "microphoneUnavailable",
                reason: "マイクを開始できなかった。\(error.localizedDescription)",
                before: bytes,
                after: bytes,
                peak: bytes,
                details: details
            )
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            let bytes = MemoryFootprint.bytes()
            return ProbeRun.finished(
                probe: .speechMic,
                runIndex: runIndex,
                available: false,
                code: "microphoneUnavailable",
                reason: "マイクの音声フォーマットを取れない。",
                before: bytes,
                after: bytes,
                peak: bytes,
                details: details
            )
        }

        var tapInstalled = false
        do {
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
        } catch {
            engine.stop()
            if tapInstalled {
                input.removeTap(onBus: 0)
            }
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            let bytes = MemoryFootprint.bytes()
            return ProbeRun.finished(
                probe: .speechMic,
                runIndex: runIndex,
                available: false,
                code: "microphoneUnavailable",
                reason: "マイクを開始できなかった。\(error.localizedDescription)",
                before: bytes,
                after: bytes,
                peak: bytes,
                details: details
            )
        }

        let before = MemoryFootprint.bytes()
        let monitor = FootprintMonitor(start: before)
        monitor.start()
        let outcome = await OnDeviceRecognition.recognize(
            recognizer: recognizer,
            request: request,
            timeoutNanoseconds: 15_000_000_000
        ) {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            request.endAudio()
        }
        engine.stop()
        input.removeTap(onBus: 0)
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        let after = MemoryFootprint.bytes()
        let peak = max(monitor.stop(), before, after)
        details["requiresOnDeviceRecognition"] = "true"
        let interpreted = interpret(
            first: outcome,
            warm: nil,
            fallbackReason: "マイクの端末内認識が終わった。"
        )
        return ProbeRun.finished(
            probe: .speechMic,
            runIndex: runIndex,
            available: interpreted.available,
            code: interpreted.code,
            reason: interpreted.reason,
            first: outcome.totalSeconds,
            warm: nil,
            before: before,
            after: after,
            peak: peak,
            outputText: interpreted.output,
            notes: interpreted.notes + ["4 秒間の録音時間を秒数に含む。ウォームは測らない。"],
            details: details
        )
    }
}

private struct SpeechInterpretation {
    var available: Bool
    var code: String
    var reason: String
    var output: String
    var notes: [String]
}

private func interpret(
    first: RecognitionOutcome,
    warm: RecognitionOutcome?,
    fallbackReason: String
) -> SpeechInterpretation {
    let output = [
        "初回: \(first.transcript)",
        warm.map { "ウォーム: \($0.transcript)" },
    ]
    .compactMap { $0 }
    .joined(separator: "\n")
    var notes: [String] = []
    if first.transcript.isEmpty {
        notes.append("初回の認識結果は空だった。")
    }
    if let warm, warm.transcript.isEmpty {
        notes.append("ウォームの認識結果は空だった。")
    }
    let warmFinished = warm?.finished ?? true
    if first.finished, warmFinished {
        return SpeechInterpretation(
            available: true,
            code: "available",
            reason: fallbackReason,
            output: output,
            notes: notes
        )
    }
    let error = [first.error, warm?.error].compactMap { $0 }.joined(separator: " / ")
    let incomplete = !first.transcript.isEmpty || (warm?.transcript.isEmpty == false)
    return SpeechInterpretation(
        available: false,
        code: incomplete ? "recognitionIncomplete" : "onDeviceFailed",
        reason: error.isEmpty ? "端末内認識が完了しなかった。" : error,
        output: output,
        notes: notes + ["サーバ認識へは切り替えない。"]
    )
}

private func baseDetails(
    supportsOnDevice: Bool,
    mayRun: Bool,
    authorization: SpeechAuthState
) -> [String: String] {
    let locales = SFSpeechRecognizer.supportedLocales()
    let hasJapanese = locales.contains { $0.identifier.lowercased().hasPrefix("ja") }
    return [
        "supportsOnDeviceRecognition": supportsOnDevice ? "true" : "false",
        "requiresOnDeviceRecognition": mayRun ? "true" : "not-run",
        "authorization": String(describing: authorization),
        "jaInSupportedLocales": hasJapanese ? "true" : "false",
    ]
}

private func audioDescription(_ url: URL) -> [String: String]? {
    guard let file = try? AVAudioFile(forReading: url) else { return nil }
    let seconds = Double(file.length) / file.fileFormat.sampleRate
    return [
        "audioSeconds": String(seconds),
        "sampleRate": String(file.fileFormat.sampleRate),
        "channels": String(file.fileFormat.channelCount),
    ]
}
#endif
