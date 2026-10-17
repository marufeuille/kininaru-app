import SwiftUI

struct QuestionView: View {
    @Bindable var model: AppModel
    @State private var fieldEditor = QuestionFieldEditor()
    @ScaledMetric(relativeTo: .title2) private var micSide: CGFloat = 80
    @ScaledMetric(relativeTo: .body) private var searchMinHeight: CGFloat = 56
    #if DEBUG
    @State private var showsMeasurement = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("きになることをきいてみよう")
                        .font(.largeTitle)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("questionHeading")
                    Text("ことばで質問できます。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(usageLabel)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("usageCount")
                }
                .frame(maxWidth: ScreenMetrics.readableWidth, alignment: .leading)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)

            inputBar
        }
        .navigationTitle("質問")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            #if DEBUG
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showsMeasurement = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("計測")
                .accessibilityHint("開発用の計測画面を開きます")
                .accessibilityIdentifier("measurementButton")
            }
            #endif
            ToolbarItem(placement: .topBarTrailing) {
                Button("履歴") {
                    model.showHistory()
                }
                .accessibilityIdentifier("historyButton")
            }
        }
        #if DEBUG
        .navigationDestination(isPresented: $showsMeasurement) {
            MeasurementView()
        }
        #endif
    }

    private var usageLabel: String {
        "つかった回数: \(model.usageCount)"
    }

    /// 調べるは入力欄の下、画面下端に置く。キーボードの安全領域の上に残るので、縦でも横でも隠れない。
    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                QuestionTextField(text: $model.draft, editor: fieldEditor) {
                    model.submitQuestion()
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)

                micButton
            }
            HStack(alignment: .center, spacing: 16) {
                searchButton
                Color.clear
                    .frame(width: micSide, height: 1)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: ScreenMetrics.readableWidth)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    /// 音声は追加スパイクのあと。見た目だけ残し、許可は求めない。
    private var micButton: some View {
        Button {} label: {
            VStack(spacing: 2) {
                Image(systemName: "mic.fill")
                    .font(.title2)
                Text("あとで")
                    .font(.caption2)
            }
            .frame(minWidth: micSide, minHeight: micSide)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .disabled(true)
        .accessibilityLabel("マイク")
        .accessibilityHint("音声入力は、このあとで使えるようにします")
        .accessibilityValue(model.microphoneAvailability)
        .accessibilityIdentifier("micButton")
    }

    private var searchButton: some View {
        Button {
            // 変換中に調べると、確定前の範囲が残って次の表示へ古い文字が戻ることがある。先に確定する。
            fieldEditor.commitComposition()
            model.submitQuestion()
        } label: {
            Text("調べる")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: searchMinHeight)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canSearch)
        .accessibilityIdentifier("searchButton")
    }
}
