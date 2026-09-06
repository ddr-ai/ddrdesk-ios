import SwiftUI

struct SessionView: View {
    @ObservedObject var session: DeskSession
    @State private var keyboardOn = true
    @State private var lastOrientation = OrientationName.current()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RemoteScreen(sink: session.video, onReady: {
                session.requestKeyframe()
            })
                .ignoresSafeArea()
                .allowsHitTesting(false)

            CursorLayer(cursor: session.cursor)
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
                .frame(width: 8, height: 8)
                .opacity(0.02)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            keyboardOn = true
            session.sendViewport()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let now = OrientationName.current()
                if now != lastOrientation {
                    lastOrientation = now
                    // Relayout only. Do not tear down the decoder; the host keeps
                    // the same landscape encode and the layer letterboxes.
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

/// Host hardware cursor is a separate DRM plane, so it is not in the video.
/// Draw the pointer locally from coordinates the host sends.
struct CursorLayer: View {
    var cursor: CursorPos?

    var body: some View {
        GeometryReader { geo in
            if let c = cursor, c.visible, c.w > 0, c.h > 0 {
                let box = geo.size
                let content = CGSize(width: CGFloat(c.w), height: CGFloat(c.h))
                let scale = min(box.width / content.width, box.height / content.height)
                let w = content.width * scale
                let h = content.height * scale
                let ox = (box.width - w) / 2
                let oy = (box.height - h) / 2
                let px = ox + CGFloat(c.x) / CGFloat(c.w) * w
                let py = oy + CGFloat(c.y) / CGFloat(c.h) * h
                PointerShape()
                    .frame(width: 22, height: 28)
                    .position(x: px + 6, y: py + 10)
            }
        }
    }
}

struct PointerShape: View {
    var body: some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 1, x: 0, y: 1)
    }
}
