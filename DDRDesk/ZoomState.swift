import SwiftUI

/// Pinch-zoom of the remote picture. Stays until pinch again or Reset.
final class ZoomState: ObservableObject {
    @Published var scale: CGFloat = 1
    @Published var offset: CGSize = .zero
    var viewSize: CGSize = .zero

    static let minScale: CGFloat = 1
    static let maxScale: CGFloat = 5

    func pinch(base: CGFloat, factor: CGFloat) {
        scale = min(Self.maxScale, max(Self.minScale, base * factor))
        if scale <= 1.02 {
            scale = 1
            offset = .zero
        } else {
            clampOffset()
        }
    }

    func pan(by delta: CGSize) {
        guard scale > 1 else { return }
        offset = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
        clampOffset()
    }

    /// Pointer moved (dx, dy) in view points. Shift the picture so overflow
    /// in that direction comes on-screen.
    func followCursor(dx: CGFloat, dy: CGFloat) {
        guard scale > 1 else { return }
        offset = CGSize(width: offset.width - dx, height: offset.height - dy)
        clampOffset()
    }

    func clampOffset() {
        let s = max(scale, 1)
        let maxX = max(0, viewSize.width * (s - 1) / 2)
        let maxY = max(0, viewSize.height * (s - 1) / 2)
        offset.width = min(maxX, max(-maxX, offset.width))
        offset.height = min(maxY, max(-maxY, offset.height))
    }

    func reset() {
        scale = 1
        offset = .zero
    }
}
