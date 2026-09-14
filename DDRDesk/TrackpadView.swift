import SwiftUI
import UIKit

/// Touchscreen as a relative trackpad:
/// one-finger drag = move, tap = left click, quick double-tap = right click.
/// Hold 1.5s then drag = text select (left-button drag); release = copy.
/// Pinch = zoom the picture; two-finger drag = pan when zoomed.
struct TrackpadView: UIViewRepresentable {
    var session: DeskSession
    var zoom: ZoomState
    var onTapKeyboard: () -> Void

    func makeUIView(context: Context) -> TrackpadUIView {
        let v = TrackpadUIView()
        v.session = session
        v.zoom = zoom
        v.onTapKeyboard = onTapKeyboard
        return v
    }

    func updateUIView(_ uiView: TrackpadUIView, context: Context) {
        uiView.session = session
        uiView.zoom = zoom
        uiView.onTapKeyboard = onTapKeyboard
    }
}

final class TrackpadUIView: UIView, UIGestureRecognizerDelegate {
    weak var session: DeskSession?
    var zoom: ZoomState?
    var onTapKeyboard: (() -> Void)?

    private var last: CGPoint?
    private var moved = false
    private var pendingLeft: DispatchWorkItem?
    private var lastTapAt: TimeInterval = 0
    private let doubleTapWindow: TimeInterval = 0.28
    private var pinchBase: CGFloat = 1
    private var lastPan: CGPoint = .zero

    private var fingerDown = false
    private var selecting = false
    private var holdWork: DispatchWorkItem?
    private let holdToSelect: TimeInterval = 1.5
    private let holdSlop: CGFloat = 12
    private var holdOrigin: CGPoint = .zero
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isExclusiveTouch = false
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        pinch.delegate = self
        pinch.cancelsTouchesInView = true
        addGestureRecognizer(pinch)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onTwoFingerPan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        pan.cancelsTouchesInView = true
        addGestureRecognizer(pan)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        guard let zoom else { return }
        if g.state == .began {
            pinchBase = zoom.scale
            abortSelectWithoutCopy()
            cancelPendingLeft()
        }
        zoom.viewSize = bounds.size
        zoom.pinch(base: pinchBase, factor: g.scale)
        zoom.objectWillChange.send()
    }

    @objc private func onTwoFingerPan(_ g: UIPanGestureRecognizer) {
        guard let zoom, zoom.scale > 1 else { return }
        let p = g.translation(in: self)
        if g.state == .began {
            lastPan = p
            abortSelectWithoutCopy()
            cancelPendingLeft()
        }
        let dx = p.x - lastPan.x
        let dy = p.y - lastPan.y
        lastPan = p
        zoom.pan(by: CGSize(width: dx, height: dy))
        zoom.objectWillChange.send()
        if g.state == .ended || g.state == .cancelled {
            lastPan = .zero
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if (event?.allTouches?.count ?? touches.count) >= 2 {
            abortSelectWithoutCopy()
            cancelPendingLeft()
            last = nil
            return
        }
        moved = false
        selecting = false
        fingerDown = true
        let p = touches.first?.location(in: self) ?? .zero
        last = p
        holdOrigin = p
        scheduleHoldToSelect()
        onTapKeyboard?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if (event?.allTouches?.count ?? touches.count) >= 2 { return }
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        if selecting {
            if let last {
                let dx = Float(p.x - last.x)
                let dy = Float(p.y - last.y)
                if abs(dx) + abs(dy) > 0.5 {
                    session?.sendInput(InputJSON.move(dx: dx, dy: dy))
                    followZoom(dx: CGFloat(dx), dy: CGFloat(dy))
                }
            }
            self.last = p
            return
        }
        let slop = hypot(p.x - holdOrigin.x, p.y - holdOrigin.y)
        if slop > holdSlop {
            cancelHold()
            if let last {
                let dx = Float(p.x - last.x)
                let dy = Float(p.y - last.y)
                if abs(dx) + abs(dy) > 0.5 {
                    moved = true
                    cancelPendingLeft()
                    session?.sendInput(InputJSON.move(dx: dx, dy: dy))
                    followZoom(dx: CGFloat(dx), dy: CGFloat(dy))
                }
            }
        }
        self.last = p
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer {
            last = nil
            fingerDown = false
        }
        if selecting {
            finishSelectAndCopy()
            moved = false
            return
        }
        cancelHold()
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
        abortSelectWithoutCopy()
        last = nil
        moved = false
        fingerDown = false
        cancelPendingLeft()
    }

    private func cancelPendingLeft() {
        pendingLeft?.cancel()
        pendingLeft = nil
    }

    private func scheduleHoldToSelect() {
        cancelHold()
        haptic.prepare()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.fingerDown, !self.selecting else { return }
            self.beginSelect()
        }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + holdToSelect, execute: work)
    }

    private func cancelHold() {
        holdWork?.cancel()
        holdWork = nil
    }

    private func beginSelect() {
        cancelHold()
        cancelPendingLeft()
        selecting = true
        moved = true
        session?.sendInput(InputJSON.btn("left", down: true))
        haptic.impactOccurred()
    }

    private func finishSelectAndCopy() {
        cancelHold()
        selecting = false
        session?.sendInput(InputJSON.btn("left", down: false))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.sendCopy()
        }
    }

    private func abortSelectWithoutCopy() {
        cancelHold()
        if selecting {
            selecting = false
            session?.sendInput(InputJSON.btn("left", down: false))
        }
    }

    private func followZoom(dx: CGFloat, dy: CGFloat) {
        guard let zoom, zoom.scale > 1 else { return }
        zoom.viewSize = bounds.size
        zoom.followCursor(dx: dx, dy: dy)
        zoom.objectWillChange.send()
    }

    private func click(_ b: String) {
        session?.sendInput(InputJSON.btn(b, down: true))
        session?.sendInput(InputJSON.btn(b, down: false))
    }

    private func sendCopy() {
        session?.sendInput(InputJSON.key("ctrl", down: true))
        session?.sendInput(InputJSON.key("c", down: true))
        session?.sendInput(InputJSON.key("c", down: false))
        session?.sendInput(InputJSON.key("ctrl", down: false))
    }
}
