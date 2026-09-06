import SwiftUI
import AVFoundation

/// Hosts `VideoSink.layer` and keeps it aspect-fit (entire desktop visible, no pan/zoom).
struct RemoteScreen: UIViewRepresentable {
    let sink: VideoSink

    func makeUIView(context: Context) -> HostView {
        let v = HostView()
        v.sink = sink
        v.backgroundColor = .black
        v.layer.addSublayer(sink.layer)
        sink.layer.videoGravity = .resizeAspect
        sink.layer.backgroundColor = UIColor.black.cgColor
        return v
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        uiView.sink = sink
        uiView.setNeedsLayout()
    }

    final class HostView: UIView {
        var sink: VideoSink?
        override func layoutSubviews() {
            super.layoutSubviews()
            sink?.layer.frame = bounds
        }
    }
}
