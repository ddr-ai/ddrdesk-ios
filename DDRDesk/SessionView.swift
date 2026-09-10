import SwiftUI

struct SessionView: View {
    @ObservedObject var session: DeskSession
    @State private var keyboardOn = true
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

            VStack {
                statusBar
                Spacer()
                HStack {
                    Button {
                        keyboardOn.toggle()
                        if keyboardOn {
                            kbAnchor.focus()
                        } else {
                            kbAnchor.blur()
                        }
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
            keyboardOn = true
            session.sendViewport()
            kbAnchor.focus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let now = OrientationName.current()
                if now != lastOrientation {
                    lastOrientation = now
                    zoom.reset()
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
