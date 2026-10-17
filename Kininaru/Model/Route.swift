import Foundation

struct AnswerPresentation: Equatable, Hashable, Sendable {
    var question: String
    var body: String
}

enum Route: Equatable, Hashable {
    case history
    case answer(AnswerPresentation)
}
