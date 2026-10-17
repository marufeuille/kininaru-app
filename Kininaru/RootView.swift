import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack(path: $model.path) {
            QuestionView(model: model)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .history:
                        HistoryView(model: model)
                    case .answer(let presentation):
                        AnswerView(model: model, presentation: presentation)
                    }
                }
        }
    }
}
