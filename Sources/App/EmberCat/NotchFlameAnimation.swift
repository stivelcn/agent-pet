import Foundation

/// Continuous heat, phase and color transitions, driven only by output tok/s.
struct NotchFlameAnimation {
    private(set) var heat: Double = 0
    private(set) var visibility: Double = 0
    private(set) var phase: Double = 8.73
    private(set) var targetHeat: Double = 0
    private var targetVisibility: Double = 0
    private(set) var color = NotchFlamePalette.standard.color(for: 0)
    private var targetColor = NotchFlamePalette.standard.color(for: 0)

    static func heat(for speed: Double) -> Double {
        guard speed.isFinite else { return 0 }
        return pow(min(1, max(0, speed / 180)), 0.80)
    }

    mutating func setSpeed(_ speed: Double, active: Bool = true, color: SIMD3<Float>? = nil) {
        if let color {
            targetColor = color
            if isHidden { self.color = color }
        }
        targetHeat = active ? Self.heat(for: speed) : 0
        targetVisibility = targetHeat > 0 ? 1 : 0
    }

    mutating func advance(by elapsed: TimeInterval, reduceMotion: Bool = false, flow: Double = 1) {
        guard elapsed.isFinite, elapsed > 0 else { return }
        let delta = min(0.1, elapsed)
        let heatTime = targetHeat < heat ? 0.48 : 0.36
        heat += (targetHeat - heat) * (1 - exp(-delta / heatTime))
        visibility += (targetVisibility - visibility)
            * (1 - exp(-delta / (targetVisibility > visibility ? 0.16 : 0.48)))
        if abs(targetHeat - heat) < 0.0004 { heat = targetHeat }
        if abs(targetVisibility - visibility) < 0.0004 { visibility = targetVisibility }
        color += (targetColor - color) * Float(1 - exp(-delta / 0.22))
        if colorDistance < 0.0004 { color = targetColor }
        if !reduceMotion {
            let multiplier = flow.isFinite ? min(2.5, max(0.25, flow)) : 1
            phase += delta * (0.22 + heat + 0.50 * heat * heat) * multiplier
        }
    }

    var isHidden: Bool { heat == 0 && visibility == 0 }

    func needsFrames(reduceMotion: Bool) -> Bool {
        guard !isHidden || targetHeat > 0 else { return false }
        return !reduceMotion || heat != targetHeat || visibility != targetVisibility || color != targetColor
    }

    private var colorDistance: Float {
        max(abs(color.x - targetColor.x), abs(color.y - targetColor.y), abs(color.z - targetColor.z))
    }

    mutating func reset() {
        heat = 0
        targetHeat = 0
        visibility = 0
        targetVisibility = 0
        color = targetColor
    }
}
