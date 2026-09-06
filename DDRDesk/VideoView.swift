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
        v.attach()
        return v
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        uiView.sink = sink
        uiView.onReady = { context.coordinator.onReady() }
        uiView.attach()
    }

    final class Coord {
        var onReady: () -> Void
        init(onReady: @escaping () -> Void) { self.onReady = onReady }
    }

    final class HostView: UIView {
        var sink: VideoSink?
        var onReady: (() -> Void)?
        private var didReady = false

        func attach() {
            guard let layer = sink?.layer else { return }
            layer.videoGravity = .resizeAspect
            layer.backgroundColor = UIColor.black.cgColor
            if layer.superlayer !== self.layer {
                layer.removeFromSuperlayer()
                self.layer.addSublayer(layer)
            }
            layer.frame = bounds
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            sink?.layer.frame = bounds
            sink?.layer.videoGravity = .resizeAspect
            if bounds.width > 2, bounds.height > 2, !didReady {
                didReady = true
                onReady?()
            }
        }
    }
}
