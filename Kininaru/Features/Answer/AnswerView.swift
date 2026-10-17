import SwiftUI

struct AnswerView: View {
    var model: AppModel
    let presentation: AnswerPresentation
    @State private var showsSourceNote = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("きいたこと")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(presentation.question)
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("answerQuestion")

                    Text("答え")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(presentation.body)
                        .font(.body)
                        .accessibilityIdentifier("answerBody")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(
                            Color(uiColor: .secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 16)
                        )

                    Button("くわしくはここ") {
                        showsSourceNote = true
                    }
                    .font(.headline)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("sourceButton")

                    if showsSourceNote {
                        Text("出典のページは、このあとで開くようにします。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("sourceNote")
                    }
                }
                .padding()
                .frame(maxWidth: ScreenMetrics.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

            Button {
                model.askNextQuestion()
            } label: {
                Text("つぎの質問")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("nextQuestionButton")
            .padding()
            .frame(maxWidth: ScreenMetrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("答え")
        .navigationBarTitleDisplayMode(.inline)
    }
}
