import SwiftUI
import UIKit

@MainActor
struct MeasurementView: View {
    @State private var model = SpikeModel()
    @State private var speaker = SampleSpeaker()
    @State private var job: Task<Void, Never>?
    @State private var markdownURL: URL?
    @State private var jsonURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                deviceCard
                controls
                FuriganaPreview()
                if !model.report.summaries.isEmpty {
                    summarySection
                }
                proposalSection
                exportSection
            }
            .padding()
            .frame(maxWidth: ScreenMetrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("計測")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshExports() }
        .onDisappear { job?.cancel() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("端末内の計測")
                .font(.largeTitle)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("measurementHeading")
            Text("子ども向けの操作ではありません。通信はしません。入力欄の質問は使いません。")
                .font(.body)
                .foregroundStyle(.secondary)
            #if canImport(FoundationModels)
            Text("このビルドは FoundationModels を含みます。答えの理由コードを記録できます。")
                .font(.body)
            #else
            Text("このビルドの SDK に FoundationModels がありません。deviceNotEligible などを取るには、Xcode 26 以降で入れ直してください。")
                .font(.body)
            #endif
        }
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.device.marketingName)
                .font(.headline)
            Text("\(model.device.modelIdentifier) / \(model.device.systemName) \(model.device.systemVersion)")
                .font(.body.monospacedDigit())
            Text(model.device.isSimulator ? "シミュレータです。この数値は採用しません。" : "実機です。")
                .font(.body)
                .foregroundStyle(.secondary)
            if model.device.isLikelyA16iPad {
                Text("iPad (A16) です。答えは deviceNotEligible になる見込みです。")
                    .font(.body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.status)
                .font(.body)
                .accessibilityIdentifier("measurementStatus")
            if model.isRunning {
                ProgressView()
            }
            if let notice = model.notice {
                Text(notice)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Button {
                job?.cancel()
                job = Task { await runSuite() }
            } label: {
                Text("3回測る")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isRunning)
            .accessibilityIdentifier("runSuiteButton")

            Text("ふりがな、読み上げ、音声ファイル、答えを、それぞれ \(SpikePlan.runsPerProbe) 回測ります。各回は初回とウォームです。中央値は書き出しに入ります。マイクは入りません。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                job?.cancel()
                job = Task { await runMic() }
            } label: {
                Text("マイクで4秒測る")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(model.isRunning)
            .accessibilityIdentifier("runMicButton")

            Button {
                speaker.speak()
            } label: {
                Text("読み上げを聞く")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(model.isRunning)
            .accessibilityIdentifier("speakSampleButton")
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("中央値")
                .font(.headline)
            ForEach(model.report.summaries, id: \.probe) { summary in
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title)
                        .font(.headline)
                    Text(summary.available ? "可" : "不可")
                        .font(.body)
                    Text(summary.availabilityCode)
                        .font(.body.monospaced())
                    Text("初回 \(SpikeReportMarkdown.seconds(summary.medianFirstSeconds)) 秒 / ウォーム \(SpikeReportMarkdown.seconds(summary.medianWarmSeconds)) 秒")
                        .font(.body.monospacedDigit())
                    Text("終了 \(SpikeReportMarkdown.mebibytes(summary.medianMemoryAfterBytes)) MiB / ピーク \(SpikeReportMarkdown.mebibytes(summary.medianMemoryPeakBytes)) MiB")
                        .font(.body.monospacedDigit())
                    Text(summary.reason)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            ForEach(model.runs) { run in
                DisclosureGroup("\(run.probe.title) \(run.runIndex) 回目") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(run.reason)
                            .font(.body)
                        if let output = run.outputText, !output.isEmpty {
                            Text(output)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        ForEach(Array(run.notes.enumerated()), id: \.offset) { _, note in
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var proposalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("答えの組み立て場所")
                .font(.headline)
            Text(model.report.proposal)
                .font(.body)
                .textSelection(.enabled)
            Text("端末内の代替")
                .font(.headline)
            ForEach(model.report.onDeviceAlternatives, id: \.self) { line in
                Text(line)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("書き出し")
                .font(.headline)
            Button {
                copy(SpikeReportMarkdown.render(model.report), notice: "Markdown をコピーしました。")
            } label: {
                Text("Markdown をコピー")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("copyMarkdownButton")

            Button {
                do {
                    copy(try SpikeReportJSON.string(model.report), notice: "JSON をコピーしました。")
                } catch {
                    model.notice = "JSON の作成に失敗しました。"
                }
            } label: {
                Text("JSON をコピー")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("copyJSONButton")

            if let markdownURL {
                ShareLink(item: markdownURL) {
                    Text("Markdown を共有")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("shareMarkdownButton")
            }
            if let jsonURL {
                ShareLink(item: jsonURL) {
                    Text("JSON を共有")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("shareJSONButton")
            }
        }
    }

    private func runSuite() async {
        await model.runAutomaticSuite()
        refreshExports()
    }

    private func runMic() async {
        await model.runMicrophone()
        refreshExports()
    }

    private func refreshExports() {
        do {
            let urls = try SpikeExport.write(model.report)
            markdownURL = urls.markdown
            jsonURL = urls.json
        } catch {
            model.notice = "ファイルの書き出しに失敗しました。"
        }
    }

    private func copy(_ text: String, notice: String) {
        UIPasteboard.general.string = text
        model.notice = notice
    }
}

private struct FuriganaPreview: View {
    @State private var lines: [(sentence: String, tokens: [FuriganaToken], notes: [String])] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ふりがなの見本")
                .font(.headline)
            Text(FuriganaQuality.renderingLimit)
                .font(.body)
                .foregroundStyle(.secondary)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 4) {
                    RubyLine(tokens: line.tokens)
                        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                    if line.notes.isEmpty {
                        Text("\(line.sentence): 期待どおりの読みでした。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(line.notes.enumerated()), id: \.offset) { _, note in
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .onAppear {
            guard lines.isEmpty else { return }
            lines = FuriganaSamples.all.map { sample in
                let tokens = FuriganaReading.tokenize(sample.sentence)
                return (sample.sentence, tokens, FuriganaQuality.notes(tokens: tokens, sample: sample))
            }
        }
    }
}
