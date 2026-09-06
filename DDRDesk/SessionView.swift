import SwiftUI

struct SessionView: View {
    @ObservedObject var session: DeskSession
    @State private var keyboardOn = true
    @State private var lastOrientation = OrientationName.current()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RemoteScreen(sink: session.video)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            TrackpadView(session: session, onTapKeyboard: { keyboardOn = true })
                .ignoresSafeArea()

            VStack {
                statusBar
                Spacer()
                HStack {
                    Button {
                        keyboardOn.toggle()
                    } label: {
                        Image(systemName: keyboardOn ? "keyboard.fill" : "keyboard")
                            .font(.title2)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Toggle keyboard")
                    Spacer()
                    Button {
                        session.disconnect()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Disconnect")
                }
                .padding()
            }

            KeyboardHost(session: session, focused: $keyboardOn)
                .frame(width: 1, height: 1)
                .opacity(0.01)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            keyboardOn = true
            session.sendViewport()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                let now = OrientationName.current()
                if now != lastOrientation {
                    lastOrientation = now
                    session.sendViewport()
                }
            }
        }
        .onChange(of: session.state) { _, new in
            if case .streaming = new {
                session.sendViewport()
            }
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        switch session.state {
        case .streaming:
            EmptyView()
        case .reconnecting(let why):
            banner("Disconnected — retrying…  \(why)", color: .orange)
        case .connecting, .searching, .authenticating:
            banner(session.statusLine.isEmpty ? "Connecting…" : session.statusLine, color: .blue)
        case .failed(let e):
            banner(e, color: .red)
        default:
            EmptyView()
        }
    }

    private func banner(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(color.opacity(0.85), in: Capsule())
            .padding(.top, 8)
    }
}
