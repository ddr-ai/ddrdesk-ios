import SwiftUI
import UIKit

/// Hidden first-responder that surfaces the **system** iOS keyboard.
/// Inserts and deletes are forwarded as native text/key events — no custom keyboard.
struct KeyboardHost: UIViewRepresentable {
    var session: DeskSession
    @Binding var focused: Bool

    func makeCoordinator() -> Coord { Coord(session: session) }

    func makeUIView(context: Context) -> HiddenField {
        let f = HiddenField()
        f.coordinator = context.coordinator
        f.autocorrectionType = .no
        f.autocapitalizationType = .none
        f.spellCheckingType = .no
        f.smartDashesType = .no
        f.smartQuotesType = .no
        f.smartInsertDeleteType = .no
        f.textContentType = .none
        f.keyboardType = .default
        f.returnKeyType = .default
        f.backgroundColor = .clear
        f.tintColor = .clear
        f.textColor = .clear
        return f
    }

    func updateUIView(_ uiView: HiddenField, context: Context) {
        context.coordinator.session = session
        uiView.coordinator = context.coordinator
        if focused && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !focused && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coord: NSObject, UITextFieldDelegate {
        var session: DeskSession
        init(session: DeskSession) { self.session = session }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string.isEmpty {
                session.sendInput(InputJSON.key("backspace", down: true))
                session.sendInput(InputJSON.key("backspace", down: false))
            } else {
                session.sendInput(InputJSON.text(string))
            }
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            session.sendInput(InputJSON.key("return", down: true))
            session.sendInput(InputJSON.key("return", down: false))
            return false
        }
    }
}

final class HiddenField: UITextField {
    var coordinator: KeyboardHost.Coord?

    override var canBecomeFirstResponder: Bool { true }

    override func caretRect(for position: UITextPosition) -> CGRect { .zero }
    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { [] }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(esc)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(up)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(down)),
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(left)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(right)),
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(tab)),
        ]
    }

    @objc func esc() { tap("escape") }
    @objc func up() { tap("up") }
    @objc func down() { tap("down") }
    @objc func left() { tap("left") }
    @objc func right() { tap("right") }
    @objc func tab() { tap("tab") }

    private func tap(_ k: String) {
        coordinator?.session.sendInput(InputJSON.key(k, down: true))
        coordinator?.session.sendInput(InputJSON.key(k, down: false))
    }
}
