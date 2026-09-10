import SwiftUI
import AVFoundation

/// Hosts `VideoSink.layer`. Pinch scale resizes the picture and stays until changed.
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
        private var scale: CGFloat = 1
        private var offset: CGSize = .zero

        func attach() {
            guard let layer = sink?.layer else { return }
            layer.videoGravity = .resizeAspect
            layer.backgroundColor = UIColor.black.cgColor
            if layer.superlayer !== self.layer {
                layer.removeFromSuperlayer()
                self.layer.addSublayer(layer)
            }
            layoutVideo()
        }

        func apply(zoom: ZoomState) {
            scale = max(1, zoom.scale)
            offset = zoom.offset
            zoom.viewSize = bounds
            layoutVideo()
        }

        private func layoutVideo() {
            guard let layer = sink?.layer else { return }
            let s = max(1, scale)
            let w = bounds.width * s
            let h = bounds.height * s
            let x = (bounds.width - w) / 2 + offset.width
            let y = (bounds.height - h) / 2 + offset.height
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.frame = CGRect(x: x, y: y, width: w, height: h)
            CATransaction.commit()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            layoutVideo()
            if bounds.width > 2, bounds.height > 2, !didReady {
                didReady = true
                onReady?()
            }
        }
    }
}
