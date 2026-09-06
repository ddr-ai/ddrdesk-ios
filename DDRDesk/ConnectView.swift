import SwiftUI

struct ConnectView: View {
    @StateObject private var session = DeskSession()
    @EnvironmentObject private var updates: UpdateService
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

            if updates.updateAvailable {
                VStack(spacing: 10) {
                    Button {
                        updates.apply()
                    } label: {
                        VStack(spacing: 4) {
                            Text("Update available — tap to install")
                                .font(.headline)
                            if let v = updates.latest {
                                Text("Build \(v.build)  (\(v.version))")
                                    .font(.caption)
                            }
                            Text("Opens AltStore, SideStore, Feather, or ESign on this phone. No Mac needed.")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.black)
                    }
                    Button("Share IPA to another installer") {
                        updates.shareIPA()
                    }
                    .font(.footnote)
                }
                .padding(.horizontal, 32)
            }

            if let last = PairingStore.shared.load().first {
                Button("Reconnect to \(last.name)  \(format(last.id))") {
                    digits = format(last.id)
                    started = true
                    session.connect(id: last.id)
                }
                .font(.subheadline)
            }

            Spacer()
            Text("v\(updates.currentVersion) (\(updates.currentBuild))  ·  No account, no relay.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom)
        }
        .padding()
        .onAppear {
            idFocused = true
            Task { await updates.check(autoInstall: true) }
        }
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
