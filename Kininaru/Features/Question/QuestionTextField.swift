import SwiftUI
import UIKit

/// 調べるボタンから、変換を確定して欄の文字列をモデルへ写す。
final class QuestionFieldEditor {
    fileprivate weak var field: UITextField?

    func commitComposition() {
        field?.resignFirstResponder()
    }
}

/// 質問の入力欄。日本語 IME の変換中も、見えている文字を保つ。
struct QuestionTextField: UIViewRepresentable {
    @Binding var text: String
    var editor: QuestionFieldEditor
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = ExpandingTextField()
        field.placeholder = "質問を入力してください"
        field.borderStyle = .roundedRect
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.returnKeyType = .search
        field.autocapitalizationType = .sentences
        field.autocorrectionType = .default
        field.accessibilityLabel = "質問"
        field.accessibilityIdentifier = "questionField"
        field.delegate = context.coordinator
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        // 横は親の幅に広がる。縦は 1 行で、余った高さを受け取らない。
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.required, for: .vertical)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        editor.field = field
        return field
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextField,
        context: Context
    ) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
        let measured = uiView.sizeThatFits(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        )
        let height = max(uiView.intrinsicContentSize.height, measured.height)
        return CGSize(width: width, height: height)
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        editor.field = uiView
        uiView.font = .preferredFont(forTextStyle: .body)
        if let replacement = QuestionFieldSync.textToApply(
            current: uiView.text ?? "",
            isComposing: uiView.markedTextRange != nil,
            external: text
        ) {
            uiView.text = replacement
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: QuestionTextField

        init(_ parent: QuestionTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ field: UITextField) {
            sync(field)
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            // 変換中の更新は editingChanged が来ないことがある。選択の変化で見えている全文を拾う。
            sync(textField)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            // 調べたあとに draft を空にした直後、終了通知が古い文字を戻すことがある。空なら欄も消す。
            let next = QuestionFieldSync.textAfterEndEditing(
                draft: parent.text,
                fieldText: textField.text ?? ""
            )
            if textField.text != next {
                textField.text = next
            }
            if parent.text != next {
                parent.text = next
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            // 変換中の改行キーは確定に使う。確定済みのときだけ調べる。
            guard textField.markedTextRange == nil else { return false }
            sync(textField)
            textField.resignFirstResponder()
            parent.onSubmit()
            return false
        }

        private func sync(_ field: UITextField) {
            // UITextField.text は変換中の文字を含む。確定分だけにすると、見えている質問とずれる。
            let visible = field.text ?? ""
            if parent.text != visible {
                parent.text = visible
            }
        }
    }
}

/// 横幅は親の提案に合わせる。高さは 1 行で、最低でも押しやすい 44pt。
private final class ExpandingTextField: UITextField {
    override var intrinsicContentSize: CGSize {
        let fitted = super.intrinsicContentSize
        return CGSize(width: UIView.noIntrinsicMetric, height: max(fitted.height, 44))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fitted = super.sizeThatFits(size)
        return CGSize(width: fitted.width, height: max(fitted.height, 44))
    }
}
