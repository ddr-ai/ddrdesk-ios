import SwiftUI

/// Pinch-zoom of the remote picture. Stays until pinch again or Reset.
final class ZoomState: ObservableObject {
    @Published var scale: CGFloat = 1
    @Published var offset: CGSize = .zero
    var viewSize: CGSize = .zero

    static let minScale: CGFloat = 1
    static let maxScale: CGFloat = 3

    func setScale(_ value: CGFloat) {
        let s = min(Self.maxScale, max(Self.minScale, value))
        if abs(s - scale) < 0.001 { return }
        scale = s
        if scale <= 1.02 {
            scale = 1
            offset = .zero
        } else {
            clampOffset()
        }
        objectWillChange.send()
    }

    func cycleScreenScale() {
        let steps: [CGFloat] = [1.0, 1.5, 2.0, 2.5, 3.0]
        let next = steps.first(where: { $0 > scale + 0.05 }) ?? 1.0
        setScale(next)
    }

    func pinch(base: CGFloat, factor: CGFloat) {
        setScale(base * factor)
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
