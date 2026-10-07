import AppKit
import QuartzCore
import SwiftUI

/// The pulse of indicators that can stay on screen for hours: an agent at
/// work, a recording, a call using the camera or microphone.
///
/// Core Animation plays it in the render server, so Atoll does no work per
/// frame. SwiftUI's repeating animations and `symbolEffect(.pulse)` instead
/// redraw on the main thread every frame, which measured at a fifth of a core
/// for as long as one ran.
enum RenderServerPulse {
    private static let key = "atoll.pulse"

    /// Starts or stops the pulse on `layer`: from full opacity and size to
    /// `minimumOpacity` and `peakScale`, and back.
    static func apply(_ isActive: Bool, to layer: CALayer, minimumOpacity: Float, peakScale: CGFloat = 1, duration: CFTimeInterval) {
        let isRunning = layer.animation(forKey: key) != nil
        if isActive, !isRunning {
            layer.add(animation(minimumOpacity: minimumOpacity, peakScale: peakScale, duration: duration), forKey: key)
        } else if !isActive, isRunning {
            layer.removeAnimation(forKey: key)
        }
    }

    private static func animation(minimumOpacity: Float, peakScale: CGFloat, duration: CFTimeInterval) -> CAAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = minimumOpacity
        var parts: [CAAnimation] = [fade]
        if peakScale != 1 {
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 1
            grow.toValue = peakScale
            parts.append(grow)
        }
        let group = CAAnimationGroup()
        group.animations = parts
        group.duration = duration
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // A slow fade needs few frames.
        group.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 30, preferred: 30)
        return group
    }
}

/// SwiftUI content that fades in and out while `isActive`. The content is
/// drawn once into its own layer, whose opacity Core Animation animates.
/// It gets no environment from the surrounding view, so it sets its own font
/// and colors.
struct LayerPulse<Content: View>: NSViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isActive: Bool
    private let reduceMotionOverride: Bool?
    let content: Content

    init(isActive: Bool, reduceMotionOverride: Bool? = nil, @ViewBuilder content: () -> Content) {
        self.isActive = isActive
        self.reduceMotionOverride = reduceMotionOverride
        self.content = content()
    }

    func makeNSView(context: Context) -> NSHostingView<Content> {
        let view = NSHostingView(rootView: content)
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSHostingView<Content>, context: Context) {
        view.rootView = content
        if let layer = view.layer {
            RenderServerPulse.apply(isActive && !(reduceMotionOverride ?? reduceMotion), to: layer, minimumOpacity: 0.35, duration: 0.9)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSHostingView<Content>, context: Context) -> CGSize? {
        nsView.fittingSize
    }
}

/// A dot that breathes: the recording indicator.
struct PulsingDot: NSViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: NSColor
    let diameter: CGFloat

    func makeNSView(context: Context) -> DotView { DotView() }

    func updateNSView(_ view: DotView, context: Context) {
        view.configure(color: color, diameter: diameter, reduceMotion: reduceMotion)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DotView, context: Context) -> CGSize? {
        CGSize(width: diameter, height: diameter)
    }

    final class DotView: NSView {
        /// A sublayer, so it grows about its centre; the view's own layer scales from a corner.
        private let dot = CAShapeLayer()
        private var reduceMotion = false

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.addSublayer(dot)
        }

        required init?(coder: NSCoder) { nil }

        func configure(color: NSColor, diameter: CGFloat, reduceMotion: Bool) {
            self.reduceMotion = reduceMotion
            RenderServerPulse.apply(window != nil && !reduceMotion, to: dot, minimumOpacity: 0.7, peakScale: 1.2, duration: 0.8)
            dot.fillColor = color.cgColor
            dot.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            dot.path = CGPath(ellipseIn: dot.bounds, transform: nil)
            needsLayout = true
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            dot.position = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.commit()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            RenderServerPulse.apply(window != nil && !reduceMotion, to: dot, minimumOpacity: 0.7, peakScale: 1.2, duration: 0.8)
        }
    }
}
