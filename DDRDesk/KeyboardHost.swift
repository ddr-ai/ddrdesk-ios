import SwiftUI
import UIKit

final class KeyboardAnchor {
    weak var field: RemoteField?
    var onDismiss: (() -> Void)?

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

    func clearDraft() {
        DispatchQueue.main.async {
            self.field?.clearDraft()
        }
    }
}

/// Visible textarea bound to the system keyboard. Keystrokes are sent to the
/// host as they happen; the local box is a live echo and is wiped when the
/// keyboard is dismissed.
struct KeyboardHost: UIViewRepresentable {
    var session: DeskSession
    var focused: Bool
    var anchor: KeyboardAnchor

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> RemoteField {
        let f = RemoteField()
        f.session = session
        f.anchor = anchor
        f.delegate = f
        f.font = UIFont.preferredFont(forTextStyle: .body)
        f.backgroundColor = UIColor.secondarySystemBackground
        f.textColor = UIColor.label
        f.layer.cornerRadius = 12
        f.layer.masksToBounds = true
        f.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        f.keyboardType = .default
        f.returnKeyType = .default
        f.autocorrectionType = .no
        f.autocapitalizationType = .none
        f.spellCheckingType = .no
        f.smartDashesType = .no
        f.smartQuotesType = .no
        f.smartInsertDeleteType = .no
        f.textContentType = nil
        f.keyboardDismissMode = .interactive
        f.placeholder = "Type on the remote desktop"
        anchor.field = f
        return f
    }

    func updateUIView(_ uiView: RemoteField, context: Context) {
        uiView.session = session
        uiView.anchor = anchor
        uiView.delegate = uiView
        anchor.field = uiView
        if focused {
            if !uiView.isFirstResponder {
                DispatchQueue.main.async { _ = uiView.becomeFirstResponder() }
            }
        } else {
            if uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
            uiView.clearDraft()
        }
    }

    final class Coordinator {}
}

final class RemoteField: UITextView, UITextViewDelegate {
    var session: DeskSession?
    weak var anchor: KeyboardAnchor?
    var placeholder: String = "" {
        didSet { placeholderLabel.text = placeholder }
    }

    private let placeholderLabel = UILabel()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.font = UIFont.preferredFont(forTextStyle: .body)
        placeholderLabel.textColor = UIColor.placeholderText
        placeholderLabel.numberOfLines = 1
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -13),
        ])
        refreshPlaceholder()
    }

    required init?(coder: NSCoder) { nil }

    func clearDraft() {
        if !text.isEmpty {
            text = ""
        }
        refreshPlaceholder()
    }

    func sendBackspace() {
        session?.sendInput(InputJSON.key("backspace", down: true))
        session?.sendInput(InputJSON.key("backspace", down: false))
    }

    func sendDelete() {
        session?.sendInput(InputJSON.key("delete", down: true))
        session?.sendInput(InputJSON.key("delete", down: false))
    }

    func sendReturn() {
        session?.sendInput(InputJSON.key("return", down: true))
        session?.sendInput(InputJSON.key("return", down: false))
    }

    override func deleteBackward() {
        if text.isEmpty {
            sendBackspace()
            return
        }
        super.deleteBackward()
        refreshPlaceholder()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText string: String) -> Bool {
        if string == "\n" {
            sendReturn()
            return true
        }
        if string.isEmpty {
            if range.length == 0 { return false }
            for _ in 0..<range.length { sendBackspace() }
            DispatchQueue.main.async { self.refreshPlaceholder() }
            return true
        }
        session?.sendInput(InputJSON.text(string))
        DispatchQueue.main.async { self.refreshPlaceholder() }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        refreshPlaceholder()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        anchor?.onDismiss?()
    }

    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool { true }

    override var canBecomeFirstResponder: Bool { true }

    private func refreshPlaceholder() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for p in presses {
            guard let key = p.key else { continue }
            switch key.keyCode {
            case .keyboardDeleteOrBackspace:
                if text.isEmpty { sendBackspace() }
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
