import SwiftUI
import UIKit

/// Touchscreen as a relative trackpad:
/// one-finger drag = move, tap = left click, two-finger tap = right click.
struct TrackpadView: UIViewRepresentable {
    var session: DeskSession
    var onTapKeyboard: () -> Void

    func makeUIView(context: Context) -> TrackpadUIView {
        let v = TrackpadUIView()
        v.session = session
        v.onTapKeyboard = onTapKeyboard
        return v
    }

    func updateUIView(_ uiView: TrackpadUIView, context: Context) {
        uiView.session = session
        uiView.onTapKeyboard = onTapKeyboard
    }
}

final class TrackpadUIView: UIView {
    weak var session: DeskSession?
    var onTapKeyboard: (() -> Void)?

    private var last: CGPoint?
    private var twoFingerTap = false
    private var moved = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isExclusiveTouch = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        twoFingerTap = (event?.allTouches?.count ?? touches.count) >= 2
        moved = false
        last = touches.first?.location(in: self)
        onTapKeyboard?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        if let last {
            let dx = Float(p.x - last.x)
            let dy = Float(p.y - last.y)
            if abs(dx) + abs(dy) > 0.5 {
                moved = true
                session?.sendInput(InputJSON.move(dx: dx, dy: dy))
            }
        }
        self.last = p
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer {
            last = nil
            twoFingerTap = false
            moved = false
        }
        if !moved {
            if twoFingerTap || (event?.allTouches?.count ?? 1) >= 2 {
                click("right")
            } else {
                click("left")
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        last = nil
        twoFingerTap = false
        moved = false
    }

    private func click(_ b: String) {
        session?.sendInput(InputJSON.btn(b, down: true))
        session?.sendInput(InputJSON.btn(b, down: false))
    }
}
