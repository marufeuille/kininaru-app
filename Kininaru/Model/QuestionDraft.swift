import Foundation

enum QuestionDraft {
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canSearch(_ text: String) -> Bool {
        submitText(visible: text) != nil
    }

    /// 画面に見えている文字列から、調べる対象を決める。空白だけなら調べない。
    /// `visible` は `UITextField.text`。変換中の文字もこの中に入っている。
    static func submitText(visible: String) -> String? {
        let text = normalized(visible)
        return text.isEmpty ? nil : text
    }
}

enum QuestionFieldSync {
    /// 外から欄へ書き戻す文字列。変換中は、入力を消すとき以外は触らない。
    /// 空文字を拒むと、つぎの質問でも変換中の文字が欄に残る。
    static func textToApply(current: String, isComposing: Bool, external: String) -> String? {
        if current == external {
            return nil
        }
        if external.isEmpty {
            return ""
        }
        if isComposing {
            return nil
        }
        return external
    }

    /// 編集が終わったときにモデルと欄へ残す文字列。
    /// モデルがすでに空なら、欄の古い文字は戻さない。
    static func textAfterEndEditing(draft: String, fieldText: String) -> String {
        draft.isEmpty ? "" : fieldText
    }
}
