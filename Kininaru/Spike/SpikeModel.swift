#if DEBUG
import Foundation
import Observation

@MainActor
@Observable
final class SpikeModel {
    var device: DeviceSnapshot
    var runs: [ProbeRun]
    var startedAt: Date
    var status: String
    var notice: String?
    var isRunning: Bool

    init() {
        device = .current()
        runs = []
        startedAt = Date()
        status = "まだ測っていません。"
        notice = nil
        isRunning = false
    }

    var report: SpikeReport {
        SpikeReport.make(device: device, runs: runs, createdAt: startedAt)
    }

    func runAutomaticSuite() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        device = .current()
        startedAt = Date()
        runs = []
        notice = nil
        status = "音声認識の許可を確認しています。許可の時間は秒数に入れません。"
        _ = await SpeechAuthorization.currentOrRequest()
        if Task.isCancelled { return }

        let total = SpikePlan.runsPerProbe
        for index in 1...total {
            if Task.isCancelled { break }
            status = "\(index)/\(total) 回目: ふりがな"
            runs.append(FuriganaProbe.measure(runIndex: index))
            if Task.isCancelled { break }
            status = "\(index)/\(total) 回目: 読み上げ"
            runs.append(await TTSProbe.measure(runIndex: index))
            if Task.isCancelled { break }
            status = "\(index)/\(total) 回目: 音声ファイル"
            runs.append(await SpeechFileProbe.measure(runIndex: index))
            if Task.isCancelled { break }
            status = "\(index)/\(total) 回目: 答えの組み立て"
            runs.append(await AnswerCompositionProbe.measure(runIndex: index))
        }
        if Task.isCancelled {
            status = "計測を止めました。ここまでの結果を書き出せます。"
        } else {
            status = "\(total) 回ずつ測りました。秒数は中央値です。"
        }
    }

    func runMicrophone() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        device = .current()
        let index = runs.filter { $0.probe == .speechMic }.count + 1
        status = "マイクで聞いています。4 秒、日本語で話してください。"
        let run = await SpeechMicProbe.measure(runIndex: index)
        if Task.isCancelled { return }
        runs.append(run)
        status = "マイクの計測が終わりました。自動の 3 回には入りません。"
    }
}
#endif
