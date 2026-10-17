import SwiftUI
import UIKit

/// 質問の入力欄。日本語 IME の変換中も、見えている文字を保つ。
struct QuestionTextField: UIViewRepresentable {
    @Binding var text: String
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
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
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
            sync(textField)
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

/// 横幅は親の提案に合わせる。プレースホルダの幅で縮まないようにする。
private final class ExpandingTextField: UITextField {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: max(super.intrinsicContentSize.height, 44))
    }
}
