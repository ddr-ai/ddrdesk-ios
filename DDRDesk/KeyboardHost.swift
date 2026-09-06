import SwiftUI
import UIKit

final class KeyboardAnchor {
    weak var field: RemoteField?
    func focus() {
        DispatchQueue.main.async {
            _ = self.field?.becomeFirstResponder()
        }
    }
    func blur() {
        DispatchQueue.main.async {
            self.field?.resignFirstResponder()
        }
    }
}

/// Visible system `UITextField` so the iOS keyboard actually stays first responder
/// and forwards inserts/deletes. A hidden 1×1 UIKeyInput view never received keys.
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

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string.isEmpty {
            session?.sendInput(InputJSON.key("backspace", down: true))
            session?.sendInput(InputJSON.key("backspace", down: false))
        } else {
            session?.sendInput(InputJSON.text(string))
        }
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        session?.sendInput(InputJSON.key("return", down: true))
        session?.sendInput(InputJSON.key("return", down: false))
        return false
    }

    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool { true }

    override var canBecomeFirstResponder: Bool { true }
}
