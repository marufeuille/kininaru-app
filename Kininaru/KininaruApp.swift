import SwiftUI

@main
struct KininaruApp: App {
    @State private var model = AppModel(
        speech: UnconfiguredSpeechCapture(),
        sources: UnconfiguredSourceFetcher(),
        answers: PlaceholderAnswerGenerator(),
        history: PlaceholderHistoryStore()
    )

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}
