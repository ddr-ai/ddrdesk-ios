import SwiftUI
import UIKit

/// Touchscreen as a relative trackpad:
/// one-finger drag = move, tap = left click, quick double-tap = right click.
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
    private var moved = false
    private var pendingLeft: DispatchWorkItem?
    private var lastTapAt: TimeInterval = 0
    private let doubleTapWindow: TimeInterval = 0.28

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .clear
        isExclusiveTouch = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
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
                cancelPendingLeft()
                session?.sendInput(InputJSON.move(dx: dx, dy: dy))
            }
        }
        self.last = p
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { last = nil }
        guard !moved else {
            moved = false
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastTapAt <= doubleTapWindow, pendingLeft != nil {
            cancelPendingLeft()
            lastTapAt = 0
            click("right")
            return
        }
        lastTapAt = now
        cancelPendingLeft()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingLeft = nil
            self?.lastTapAt = 0
            self?.click("left")
        }
        pendingLeft = work
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow, execute: work)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        last = nil
        moved = false
        cancelPendingLeft()
    }

    private func cancelPendingLeft() {
        pendingLeft?.cancel()
        pendingLeft = nil
    }

    private func click(_ b: String) {
        session?.sendInput(InputJSON.btn(b, down: true))
        session?.sendInput(InputJSON.btn(b, down: false))
    }
}
