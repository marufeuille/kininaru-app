import Foundation

enum QuestionDraft {
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canSearch(_ text: String) -> Bool {
        !normalized(text).isEmpty
    }
}
