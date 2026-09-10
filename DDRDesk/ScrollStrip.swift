import SwiftUI
import UIKit

/// Full-height transparent strip on the left edge. Vertical slides send
/// mouse-wheel events to whatever is under the host cursor.
struct ScrollStrip: UIViewRepresentable {
    var session: DeskSession

    func makeUIView(context: Context) -> ScrollStripView {
        let v = ScrollStripView()
        v.session = session
        return v
    }

    func updateUIView(_ uiView: ScrollStripView, context: Context) {
        uiView.session = session
    }
}

final class ScrollStripView: UIView {
    weak var session: DeskSession?
    private var lastY: CGFloat = 0
    private var acc: CGFloat = 0
    /// Points of finger travel per mouse-wheel notch.
    private let ptsPerNotch: CGFloat = 14

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false
        isExclusiveTouch = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastY = touches.first?.location(in: self).y ?? 0
        acc = 0
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let y = touches.first?.location(in: self).y else { return }
        let dy = y - lastY
        lastY = y
        // Finger up (negative dy) → scroll up (positive wheel).
        acc += -dy
        while acc >= ptsPerNotch {
            acc -= ptsPerNotch
            session?.sendInput(InputJSON.wheel(dx: 0, dy: 1))
        }
        while acc <= -ptsPerNotch {
            acc += ptsPerNotch
            session?.sendInput(InputJSON.wheel(dx: 0, dy: -1))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        acc = 0
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        acc = 0
    }
}
