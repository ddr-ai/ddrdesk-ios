import SwiftUI
import UIKit

/// Full-height transparent scroll zone on the **right** edge. Once a slide
/// starts, the finger can leave the strip and scrolling continues.
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
    /// Twice the previous 28pt strip.
    var stripWidth: CGFloat = 56
    private var tracking = false
    private var lastY: CGFloat = 0
    private var acc: CGFloat = 0
    private let ptsPerNotch: CGFloat = 14

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false
        isExclusiveTouch = true
    }

    required init?(coder: NSCoder) { fatalError() }

    private func inStrip(_ point: CGPoint) -> Bool {
        point.x >= bounds.width - stripWidth && bounds.contains(point)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        tracking || inStrip(point)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if tracking || inStrip(point) { return self }
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        tracking = true
        lastY = windowY(touches)
        acc = 0
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard tracking else { return }
        let y = windowY(touches)
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
        tracking = false
        acc = 0
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        tracking = false
        acc = 0
    }

    private func windowY(_ touches: Set<UITouch>) -> CGFloat {
        guard let t = touches.first, let win = window else {
            return touches.first?.location(in: self).y ?? 0
        }
        return t.location(in: win).y
    }
}
