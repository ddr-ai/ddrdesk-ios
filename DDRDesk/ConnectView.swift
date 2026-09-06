import SwiftUI

struct ConnectView: View {
    @StateObject private var session = DeskSession()
    @State private var digits = ""
    @State private var started = false
    @FocusState private var idFocused: Bool

    var body: some View {
        Group {
            if started && !isIdleOrFailed {
                SessionView(session: session)
            } else {
                connectForm
            }
        }
        .animation(.easeInOut(duration: 0.2), value: started)
    }

    private var isIdleOrFailed: Bool {
        switch session.state {
        case .idle, .failed: return true
        default: return false
        }
    }

    private var connectForm: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "desktopcomputer")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.cyan)
            Text("DDRDesk")
                .font(.largeTitle.weight(.semibold))
            Text("Enter the 9-digit ID shown on the Fedora host")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextField("000 000 000", text: $digits)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 32, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding()
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .focused($idFocused)
                .onChange(of: digits) { _, v in
                    let n = v.filter(\.isNumber).prefix(9)
                    digits = format(String(n))
                }

            if case .failed(let e) = session.state {
                Text(e).foregroundStyle(.red).font(.footnote)
            }

            Button {
                started = true
                session.connect(id: digits)
            } label: {
                Text("Connect")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(digits.filter(\.isNumber).count == 9 ? Color.cyan : Color.gray.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.black)
            }
            .disabled(digits.filter(\.isNumber).count != 9)
            .padding(.horizontal, 32)

            if let last = PairingStore.shared.load().first {
                Button("Reconnect to \(last.name)  \(format(last.id))") {
                    digits = format(last.id)
                    started = true
                    session.connect(id: last.id)
                }
                .font(.subheadline)
            }

            Spacer()
            Text("No account, no relay. The phone talks only to your laptop.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom)
        }
        .padding()
        .onAppear { idFocused = true }
        .onChange(of: session.state) { _, st in
            if case .idle = st { started = false }
            if case .failed = st { started = false }
        }
    }

    private func format(_ id: String) -> String {
        let n = id.filter(\.isNumber)
        var s = ""
        for (i, c) in n.enumerated() {
            if i == 3 || i == 6 { s.append(" ") }
            s.append(c)
        }
        return s
    }
}
