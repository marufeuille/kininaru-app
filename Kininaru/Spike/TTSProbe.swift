import AVFoundation
import Foundation

enum TTSSample {
    static let text = "太陽の光が空気の中でちらばるので、空は青く見えます。"
}

@MainActor
final class SampleSpeaker {
    private let synthesizer = AVSpeechSynthesizer()

    func speak() {
        let voices = AVSpeechSynthesisVoice.speechVoices().map {
            ListedVoice(identifier: $0.identifier, language: $0.language, quality: TTSProbe.qualityName($0.quality))
        }
        guard
            let choice = JapaneseVoicePolicy.synthesisChoice(from: voices),
            let voice = AVSpeechSynthesisVoice(identifier: choice.identifier),
            voice.quality == .default
        else {
            return
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: TTSSample.text)
        utterance.voice = voice
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }
}

enum TTSProbe {
    @MainActor
    static func measure(runIndex: Int) async -> ProbeRun {
        let voices = AVSpeechSynthesisVoice.speechVoices().map(listed)
        let japanese = voices.filter { $0.language.hasPrefix("ja") }
        let choice = JapaneseVoicePolicy.synthesisChoice(from: voices)
        var details: [String: String] = [
            "listedJapaneseVoices": japanese
                .map { "\($0.identifier) (\($0.quality))" }
                .joined(separator: "; "),
        ]
        guard let choice else {
            let bytes = MemoryFootprint.bytes()
            return ProbeRun.finished(
                probe: .tts,
                runIndex: runIndex,
                available: false,
                code: "noJapaneseVoice",
                reason: "ja の default 音声が無い。enhanced と premium は通信になり得るので使わない。",
                before: bytes,
                after: bytes,
                peak: bytes,
                details: details
            )
        }
        guard let voice = AVSpeechSynthesisVoice.speechVoices().first(where: {
            $0.identifier == choice.identifier && $0.quality == .default
        }) else {
            let bytes = MemoryFootprint.bytes()
            return ProbeRun.finished(
                probe: .tts,
                runIndex: runIndex,
                available: false,
                code: "noJapaneseVoice",
                reason: "選んだ default 音声を合成器に渡せなかった。",
                before: bytes,
                after: bytes,
                peak: bytes,
                details: details
            )
        }
        details["synthesisVoiceIdentifier"] = voice.identifier
        details["synthesisVoiceQuality"] = qualityName(voice.quality)

        let before = MemoryFootprint.bytes()
        let monitor = FootprintMonitor(start: before)
        monitor.start()
        let synthesizer = AVSpeechSynthesizer()
        let first = await synthesize(text: TTSSample.text, voice: voice, synthesizer: synthesizer)
        let mid = MemoryFootprint.bytes()
        let warm = await synthesize(text: TTSSample.text, voice: voice, synthesizer: synthesizer)
        let after = MemoryFootprint.bytes()
        let peak = max(monitor.stop(), before, mid, after)
        details["firstTotalSeconds"] = String(first.totalSeconds)
        details["warmTotalSeconds"] = String(warm.totalSeconds)
        details["firstFrameCount"] = String(first.frameCount)
        details["warmFrameCount"] = String(warm.frameCount)
        if first.sampleRate > 0 {
            details["sampleRate"] = String(first.sampleRate)
        }

        let produced = first.frameCount > 0 && warm.frameCount > 0
        let reason: String
        if produced {
            reason = "ja の default 音声で、再生せずバッファまで測った。秒数は最初のバッファまで。"
        } else {
            reason = "合成は終わったが、音声バッファが空だった。\(first.error ?? warm.error ?? "")"
        }
        return ProbeRun.finished(
            probe: .tts,
            runIndex: runIndex,
            available: produced,
            code: produced ? "available" : "synthesisProducedNoAudio",
            reason: reason,
            first: first.firstAudioSeconds,
            warm: warm.firstAudioSeconds,
            before: before,
            after: after,
            peak: peak,
            outputText: TTSSample.text,
            notes: ["自動計測ではスピーカーから出さない。"],
            details: details
        )
    }

    @MainActor
    private static func synthesize(
        text: String,
        voice: AVSpeechSynthesisVoice,
        synthesizer: AVSpeechSynthesizer
    ) async -> SynthesisTiming {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        let started = Date()
        let box = SynthesisBox()
        let timing: SynthesisTiming = await withCheckedContinuation { continuation in
            synthesizer.write(utterance) { buffer in
                let pcm = buffer as? AVAudioPCMBuffer
                let frames = Int(pcm?.frameLength ?? buffer.frameLength)
                if frames > 0 {
                    box.noteAudio(
                        frames: frames,
                        sampleRate: pcm?.format.sampleRate ?? 0,
                        at: WallClock.seconds(from: started)
                    )
                    return
                }
                let snapshot = box.snapshot(total: WallClock.seconds(from: started))
                box.finish(snapshot, continuation: continuation)
            }
            box.worker = Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if Task.isCancelled { return }
                var snapshot = box.snapshot(total: WallClock.seconds(from: started))
                snapshot.error = "時間内に合成が終わらなかった"
                box.finish(snapshot, continuation: continuation)
            }
        }
        box.worker?.cancel()
        return timing
    }

    private static func listed(_ voice: AVSpeechSynthesisVoice) -> ListedVoice {
        ListedVoice(
            identifier: voice.identifier,
            language: voice.language,
            quality: qualityName(voice.quality)
        )
    }

    static func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .default: "default"
        case .enhanced: "enhanced"
        case .premium: "premium"
        @unknown default: "unknown"
        }
    }
}

struct SynthesisTiming: Equatable {
    var firstAudioSeconds: Double?
    var totalSeconds: Double
    var frameCount: Int
    var sampleRate: Double
    var error: String?
}

private final class SynthesisBox: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private var firstAudio: Double?
    private var frames = 0
    private var sampleRate: Double = 0
    var worker: Task<Void, Never>?

    func noteAudio(frames: Int, sampleRate: Double, at seconds: Double) {
        lock.lock()
        if firstAudio == nil { firstAudio = seconds }
        self.frames += frames
        if sampleRate > 0 { self.sampleRate = sampleRate }
        lock.unlock()
    }

    func snapshot(total: Double) -> SynthesisTiming {
        lock.lock()
        defer { lock.unlock() }
        return SynthesisTiming(
            firstAudioSeconds: firstAudio,
            totalSeconds: total,
            frameCount: frames,
            sampleRate: sampleRate,
            error: nil
        )
    }

    func finish(
        _ timing: SynthesisTiming,
        continuation: CheckedContinuation<SynthesisTiming, Never>
    ) {
        lock.lock()
        let shouldResume = !done
        if shouldResume { done = true }
        lock.unlock()
        guard shouldResume else { return }
        worker?.cancel()
        continuation.resume(returning: timing)
    }
}
