import Foundation

/// 答え生成の差し込み口。S4 で端末内とクラウドを差し替える。
/// クラウド側の実装でも、質問の原文は端末の外に出さない。
protocol AnswerGenerating {
    func answer(for question: String, sources: [SourceDocument]) -> String
}

struct PlaceholderAnswerGenerator: AnswerGenerating {
    static let text = "ここに答えが入ります"

    func answer(for question: String, sources: [SourceDocument]) -> String {
        _ = question
        _ = sources
        return Self.text
    }
}
