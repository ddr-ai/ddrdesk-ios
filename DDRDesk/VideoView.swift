import SwiftUI
import AVFoundation

/// Hosts `VideoSink.layer` and keeps it aspect-fit (entire desktop visible, no pan/zoom).
struct RemoteScreen: UIViewRepresentable {
    let sink: VideoSink
    var onReady: () -> Void

    func makeCoordinator() -> Coord { Coord(onReady: onReady) }

    func makeUIView(context: Context) -> HostView {
        let v = HostView()
        v.sink = sink
        v.onReady = { context.coordinator.onReady() }
        v.backgroundColor = .black
        sink.layer.videoGravity = .resizeAspect
        sink.layer.backgroundColor = UIColor.black.cgColor
        v.layer.addSublayer(sink.layer)
        sink.layer.frame = v.bounds
        return v
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        uiView.sink = sink
        uiView.onReady = { context.coordinator.onReady() }
        uiView.setNeedsLayout()
    }

    final class Coord {
        var onReady: () -> Void
        init(onReady: @escaping () -> Void) { self.onReady = onReady }
    }

    final class HostView: UIView {
        var sink: VideoSink?
        var onReady: (() -> Void)?
        private var didReady = false
        override func layoutSubviews() {
            super.layoutSubviews()
            sink?.layer.frame = bounds
            if bounds.width > 2, bounds.height > 2, !didReady {
                didReady = true
                onReady?()
            }
        }
    }
}
