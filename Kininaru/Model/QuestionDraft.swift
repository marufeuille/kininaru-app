import Foundation

enum QuestionDraft {
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canSearch(_ text: String) -> Bool {
        submitText(visible: text) != nil
    }

    /// 画面に見えている文字列から、調べる対象を決める。空白だけなら調べない。
    static func submitText(visible: String) -> String? {
        let text = normalized(visible)
        return text.isEmpty ? nil : text
    }

    /// 確定済みと変換中を、見えている順につなぐ。変換中だけは落とさない。
    /// `committed` がすでに `marked` で終わっているときは、二重に足さない。
    static func visibleText(committed: String, marked: String) -> String {
        if marked.isEmpty || committed.hasSuffix(marked) {
            return committed
        }
        return committed + marked
    }
}

enum QuestionFieldSync {
    /// 変換中に外の文字列を欄へ戻すと、未確定の文字が消える。戻さない。
    static func textToApply(current: String, isComposing: Bool, external: String) -> String? {
        if isComposing || current == external {
            return nil
        }
        return external
    }
}
