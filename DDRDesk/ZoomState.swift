import SwiftUI

/// Pinch-zoom / two-finger pan of the remote picture. Trackpad clicks stay 1:1.
final class ZoomState: ObservableObject {
    @Published var scale: CGFloat = 1
    @Published var offset: CGSize = .zero

    static let minScale: CGFloat = 1
    static let maxScale: CGFloat = 4

    func pinch(base: CGFloat, factor: CGFloat) {
        scale = min(Self.maxScale, max(Self.minScale, base * factor))
        if scale <= 1.02 {
            scale = 1
            offset = .zero
        }
    }

    func pan(by delta: CGSize) {
        guard scale > 1 else { return }
        offset = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
        clampOffset()
    }

    func clampOffset() {
        let maxX = 600 * (scale - 1)
        let maxY = 800 * (scale - 1)
        offset.width = min(maxX, max(-maxX, offset.width))
        offset.height = min(maxY, max(-maxY, offset.height))
    }

    func reset() {
        scale = 1
        offset = .zero
    }
}
