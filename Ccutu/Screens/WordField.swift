import SwiftUI
import UIKit

/// 보내기 버튼이 Return과 같은 길로 제출하도록 입력창을 붙잡아 두는 손잡이.
@MainActor
final class WordFieldProxy {
    fileprivate weak var field: UITextField?
    fileprivate weak var coordinator: WordField.Coordinator?
    func submit() { if let field { coordinator?.fire(field) } }
}

/// 게임 단어 입력창. SwiftUI TextField는 Return에 포커스를 놓고, 한글 조합 중 Return이면
/// 조합 글자가 제출 뒤에 다시 확정돼 남는다. UITextField로 조합을 먼저 확정하고 비운 뒤
/// `false`를 돌려 키보드를 그대로 둔다.
struct WordField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var placeholder: String
    let proxy: WordFieldProxy
    var onSubmit: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> FocusField {
        let f = FocusField()
        f.delegate = context.coordinator
        f.font = UIFont(name: "BlackHanSans-Regular", size: 26) ?? .systemFont(ofSize: 26, weight: .black)
        f.textColor = .white
        f.tintColor = UIColor(Theme.accent)
        f.keyboardAppearance = .dark
        f.returnKeyType = .send
        f.autocorrectionType = .no
        f.spellCheckingType = .no
        f.autocapitalizationType = .none
        f.smartInsertDeleteType = .no
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        f.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        proxy.field = f
        proxy.coordinator = context.coordinator
        return f
    }

    func updateUIView(_ f: FocusField, context: Context) {
        context.coordinator.parent = self
        if f.markedTextRange == nil, f.text != text { f.text = text }
        if f.attributedPlaceholder?.string != placeholder {
            f.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: UIColor(Theme.dim)])
        }
        f.wantsFocus = focused
        if focused != f.isFirstResponder {
            DispatchQueue.main.async { _ = focused ? f.becomeFirstResponder() : f.resignFirstResponder() }
        }
    }

    /// 화면이 바뀌며 처음 그려질 때는 아직 창에 붙기 전이라 becomeFirstResponder가 실패한다. 창에 붙는 순간 다시 잡는다.
    final class FocusField: UITextField {
        var wantsFocus = false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if wantsFocus, window != nil, !isFirstResponder { DispatchQueue.main.async { _ = self.becomeFirstResponder() } }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: WordField
        init(_ parent: WordField) { self.parent = parent }

        @objc func changed(_ f: UITextField) { parent.text = f.text ?? "" }
        func textFieldDidBeginEditing(_ f: UITextField) { if !parent.focused { parent.focused = true } }
        func textFieldDidEndEditing(_ f: UITextField) { if parent.focused { parent.focused = false } }

        func textFieldShouldReturn(_ f: UITextField) -> Bool {
            fire(f)
            return false
        }

        func fire(_ f: UITextField) {
            f.unmarkText()                 // 조합 중인 글자를 먼저 확정해 제출에 넣는다
            let t = f.text ?? ""
            f.text = ""
            parent.text = ""
            parent.onSubmit(t)
        }
    }
}
