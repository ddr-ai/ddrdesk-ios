import SwiftUI
import AVFoundation

/// Hosts `VideoSink.layer`. Aspect-fit by default; pinch-zoom is applied as a view transform.
struct RemoteScreen: UIViewRepresentable {
    let sink: VideoSink
    @ObservedObject var zoom: ZoomState
    var onReady: () -> Void

    func makeCoordinator() -> Coord { Coord(onReady: onReady) }

    func makeUIView(context: Context) -> HostView {
        let v = HostView()
        v.sink = sink
        v.onReady = { context.coordinator.onReady() }
        v.backgroundColor = .black
        v.clipsToBounds = true
        v.attach()
        v.apply(zoom: zoom)
        return v
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        uiView.sink = sink
        uiView.onReady = { context.coordinator.onReady() }
        uiView.attach()
        uiView.apply(zoom: zoom)
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

        func apply(zoom: ZoomState) {
            transform = CGAffineTransform(translationX: zoom.offset.width, y: zoom.offset.height)
                .scaledBy(x: zoom.scale, y: zoom.scale)
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
