import SwiftUI

struct SessionView: View {
    @ObservedObject var session: DeskSession
    @State private var keyboardOn = false
    @State private var trayOpen = false
    @State private var lastOrientation = OrientationName.current()
    @State private var kbAnchor = KeyboardAnchor()
    @StateObject private var zoom = ZoomState()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RemoteScreen(sink: session.video, zoom: zoom, onReady: {
                session.requestKeyframe()
            })
                .ignoresSafeArea()
                .allowsHitTesting(false)

            TrackpadView(session: session, zoom: zoom, onTapKeyboard: {
                if keyboardOn {
                    kbAnchor.focus()
                }
            })
                .ignoresSafeArea()

            // Full-screen overlay: hits only the right strip unless a scroll is in progress.
            ScrollStrip(session: session)
                .ignoresSafeArea()

            VStack {
                statusBar
                Spacer()
            }

            HStack {
                sideTray
                Spacer()
            }
            .padding(.leading, 6)
        }
        .safeAreaInset(edge: .bottom) {
            if keyboardOn {
                KeyboardHost(session: session, focused: keyboardOn, anchor: kbAnchor)
                    .frame(height: 36)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            session.sendViewport()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let now = OrientationName.current()
                if now != lastOrientation {
                    lastOrientation = now
                    zoom.clampOffset()
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

    private var sideTray: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    trayOpen.toggle()
                }
            } label: {
                Image(systemName: trayOpen ? "chevron.left" : "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 56)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .accessibilityLabel(trayOpen ? "Hide controls" : "Show controls")

            if trayOpen {
                VStack(spacing: 10) {
                    trayButton(keyboardOn ? "keyboard.fill" : "keyboard", "Keyboard") {
                        keyboardOn.toggle()
                        if keyboardOn {
                            kbAnchor.focus()
                        } else {
                            kbAnchor.blur()
                        }
                    }
                    trayButton("arrow.down.right.and.arrow.up.left", "Fit screen") {
                        zoom.reset()
                    }
                    trayButton("xmark", "Disconnect") {
                        session.disconnect()
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: trayOpen)
    }

    private func trayButton(_ system: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.12), in: Circle())
        }
        .accessibilityLabel(label)
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
