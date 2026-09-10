import SwiftUI
import UIKit

final class KeyboardAnchor {
    weak var field: RemoteField?
    func focus() {
        DispatchQueue.main.async {
            _ = self.field?.becomeFirstResponder()
            self.field?.restoreSentinel()
        }
    }
    func blur() {
        DispatchQueue.main.async {
            self.field?.resignFirstResponder()
        }
    }
}

/// System `UITextField`. A dummy character is kept in the field so Backspace
/// still fires when iOS thinks there is nothing to delete.
struct KeyboardHost: UIViewRepresentable {
    var session: DeskSession
    var focused: Bool
    var anchor: KeyboardAnchor

    func makeUIView(context: Context) -> RemoteField {
        let f = RemoteField()
        f.session = session
        f.delegate = f
        f.placeholder = "Type on the remote desktop"
        f.borderStyle = .roundedRect
        f.backgroundColor = UIColor.secondarySystemBackground
        f.returnKeyType = .default
        f.keyboardType = .default
        f.autocorrectionType = .no
        f.autocapitalizationType = .none
        f.spellCheckingType = .no
        f.smartDashesType = .no
        f.smartQuotesType = .no
        f.smartInsertDeleteType = .no
        f.textContentType = nil
        f.enablesReturnKeyAutomatically = false
        f.restoreSentinel()
        anchor.field = f
        return f
    }

    func updateUIView(_ uiView: RemoteField, context: Context) {
        uiView.session = session
        uiView.delegate = uiView
        anchor.field = uiView
        if focused {
            if !uiView.isFirstResponder {
                DispatchQueue.main.async { _ = uiView.becomeFirstResponder() }
            }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }
}

final class RemoteField: UITextField, UITextFieldDelegate {
    var session: DeskSession?
    static let sentinel = "\u{200B}"

    func restoreSentinel() {
        if text != Self.sentinel {
            text = Self.sentinel
        }
        if let end = position(from: beginningOfDocument, offset: 1) {
            selectedTextRange = textRange(from: end, to: end)
        }
    }

    func sendBackspace() {
        session?.sendInput(InputJSON.key("backspace", down: true))
        session?.sendInput(InputJSON.key("backspace", down: false))
    }

    func sendDelete() {
        session?.sendInput(InputJSON.key("delete", down: true))
        session?.sendInput(InputJSON.key("delete", down: false))
    }

    override func deleteBackward() {
        sendBackspace()
        restoreSentinel()
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string.isEmpty {
            let n = max(1, range.length)
            for _ in 0..<n { sendBackspace() }
            DispatchQueue.main.async { self.restoreSentinel() }
            return false
        }
        session?.sendInput(InputJSON.text(string))
        DispatchQueue.main.async { self.restoreSentinel() }
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        session?.sendInput(InputJSON.key("return", down: true))
        session?.sendInput(InputJSON.key("return", down: false))
        return false
    }

    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool { true }

    override var canBecomeFirstResponder: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for p in presses {
            guard let key = p.key else { continue }
            switch key.keyCode {
            case .keyboardDeleteOrBackspace:
                sendBackspace()
                handled = true
            case .keyboardDeleteForward:
                sendDelete()
                handled = true
            default:
                break
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }
}
