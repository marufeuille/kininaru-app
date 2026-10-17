import SwiftUI

struct QuestionView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("きになることをきいてみよう")
                    .font(.largeTitle)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("questionHeading")
                Text("ことばで質問できます。")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: ScreenMetrics.readableWidth, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inputBar
        }
        .navigationTitle("質問")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("履歴") {
                    model.showHistory()
                }
                .accessibilityIdentifier("historyButton")
            }
        }
    }

    /// 調べるは入力欄の右、画面下端に置く。キーボードはこの領域の外なので、縦でも横でも隠れない。
    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let microphoneNote = model.microphoneNote {
                Text(microphoneNote)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("micNote")
            }
            HStack(alignment: .center, spacing: 12) {
                TextField("質問を入力", text: $model.draft)
                    .font(.body)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { model.submitQuestion() }
                    .accessibilityIdentifier("questionField")

                Button {
                    model.noteMicrophone()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("マイク")
                .accessibilityHint("音声入力はまだ使えません")
                .accessibilityValue(model.microphoneAvailability)
                .accessibilityIdentifier("micButton")

                Button {
                    model.submitQuestion()
                } label: {
                    Text("調べる")
                        .font(.headline)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSearch)
                .accessibilityIdentifier("searchButton")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: ScreenMetrics.readableWidth)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
