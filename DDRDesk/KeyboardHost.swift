import SwiftUI
import UIKit

/// System keyboard via UIKeyInput. Trackpad taps must not steal first-responder
/// or keystrokes never leave the phone.
struct KeyboardHost: UIViewRepresentable {
    var session: DeskSession
    @Binding var focused: Bool

    func makeCoordinator() -> Coord { Coord(session: session) }

    func makeUIView(context: Context) -> KeyCatcher {
        let v = KeyCatcher()
        v.session = session
        v.isUserInteractionEnabled = true
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: KeyCatcher, context: Context) {
        uiView.session = session
        if focused {
            _ = uiView.becomeFirstResponder()
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coord {
        var session: DeskSession
        init(session: DeskSession) { self.session = session }
    }
}

final class KeyCatcher: UIView, UIKeyInput {
    var session: DeskSession?

    override var canBecomeFirstResponder: Bool { true }
    override var canResignFirstResponder: Bool { true }

    var keyboardType: UIKeyboardType { .default }
    var autocapitalizationType: UITextAutocapitalizationType { .none }
    var autocorrectionType: UITextAutocorrectionType { .no }
    var spellCheckingType: UITextSpellCheckingType { .no }
    var smartQuotesType: UITextSmartQuotesType { .no }
    var smartDashesType: UITextSmartDashesType { .no }
    var textContentType: UITextContentType? { nil }

    var hasText: Bool { true }

    func insertText(_ text: String) {
        if text == "\n" || text == "\r" {
            session?.sendInput(InputJSON.key("return", down: true))
            session?.sendInput(InputJSON.key("return", down: false))
            return
        }
        if text == "\t" {
            session?.sendInput(InputJSON.key("tab", down: true))
            session?.sendInput(InputJSON.key("tab", down: false))
            return
        }
        session?.sendInput(InputJSON.text(text))
    }

    func deleteBackward() {
        session?.sendInput(InputJSON.key("backspace", down: true))
        session?.sendInput(InputJSON.key("backspace", down: false))
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for p in presses {
            guard let key = p.key else { continue }
            let name: String?
            switch key.keyCode {
            case .keyboardReturnOrEnter: name = "return"
            case .keyboardEscape: name = "escape"
            case .keyboardTab: name = "tab"
            case .keyboardUpArrow: name = "up"
            case .keyboardDownArrow: name = "down"
            case .keyboardLeftArrow: name = "left"
            case .keyboardRightArrow: name = "right"
            case .keyboardDeleteOrBackspace: name = "backspace"
            default: name = nil
            }
            if let name {
                session?.sendInput(InputJSON.key(name, down: true))
                handled = true
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for p in presses {
            guard let key = p.key else { continue }
            let name: String?
            switch key.keyCode {
            case .keyboardReturnOrEnter: name = "return"
            case .keyboardEscape: name = "escape"
            case .keyboardTab: name = "tab"
            case .keyboardUpArrow: name = "up"
            case .keyboardDownArrow: name = "down"
            case .keyboardLeftArrow: name = "left"
            case .keyboardRightArrow: name = "right"
            case .keyboardDeleteOrBackspace: name = "backspace"
            default: name = nil
            }
            if let name {
                session?.sendInput(InputJSON.key(name, down: false))
            }
        }
        super.pressesEnded(presses, with: event)
    }
}
