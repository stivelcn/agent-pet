import AppKit

/// Capture one screen configuration so selection and geometry can be checked without changing displays.
struct NotchScreenSnapshot {
    var name: String
    var frame: CGRect
    var scale: CGFloat = 2
    var safeAreaTop: CGFloat = 0
    var leftArea: CGRect?
    var rightArea: CGRect?
    var isBuiltIn = false
    var isActive = true
    var maximumFramesPerSecond = 60

    @MainActor static func connected() -> [Self] {
        // NSScreen orders the primary display first; NSScreen.main instead follows keyboard focus.
        NSScreen.screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let displayID = number?.uint32Value
            return Self(name: screen.localizedName, frame: screen.frame,
                scale: screen.backingScaleFactor, safeAreaTop: screen.safeAreaInsets.top,
                leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea,
                isBuiltIn: displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false,
                isActive: displayID.map { CGDisplayIsActive($0) != 0 } ?? true,
                maximumFramesPerSecond: screen.maximumFramesPerSecond)
        }
    }

    var profile: NotchDisplayProfile? {
        guard isActive, Self.valid(frame), scale.isFinite, scale > 0,
              safeAreaTop.isFinite, safeAreaTop >= 0, safeAreaTop < frame.height else { return nil }
        let tolerance = 1 / scale
        let notch: CGRect?
        if safeAreaTop > 0 {
            // Both auxiliary rectangles are already in global AppKit coordinates, measured in points.
            // Incomplete data during a display change must not create a second, guessed black island.
            guard let left = leftArea, let right = rightArea, Self.valid(left), Self.valid(right) else {
                return nil
            }
            let topBand = CGRect(x: frame.minX, y: frame.maxY - safeAreaTop,
                width: frame.width, height: safeAreaTop)
            let allowed = topBand.insetBy(dx: -tolerance, dy: -tolerance)
            guard allowed.contains(left), allowed.contains(right),
                  abs(left.maxY - frame.maxY) <= tolerance,
                  abs(right.maxY - frame.maxY) <= tolerance,
                  abs(left.minY - topBand.minY) <= tolerance,
                  abs(right.minY - topBand.minY) <= tolerance,
                  right.minX > left.maxX else { return nil }
            notch = CGRect(x: left.maxX, y: topBand.minY,
                width: right.minX - left.maxX, height: safeAreaTop)
        } else {
            guard leftArea == nil || leftArea?.isEmpty == true,
                  rightArea == nil || rightArea?.isEmpty == true else { return nil }
            notch = nil
        }
        let profile = NotchDisplayProfile(screenName: name, screenFrame: frame,
            notchFrame: notch, scale: scale, maximumFramesPerSecond: maximumFramesPerSecond)
        guard frame.insetBy(dx: -tolerance, dy: -tolerance).contains(profile.panelFrame) else { return nil }
        return profile
    }

    private static func valid(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
            rect.minX, rect.maxX, rect.minY, rect.maxY].allSatisfy(\.isFinite)
            && rect.width > 0 && rect.height > 0
    }
}

struct NotchDisplayProfile {
    let screenName: String
    let screenFrame: CGRect
    let notchFrame: CGRect?
    let scale: CGFloat
    var maximumFramesPerSecond = 60

    @MainActor static func current() -> Self? { select(from: NotchScreenSnapshot.connected()) }

    static func select(from screens: [NotchScreenSnapshot]) -> Self? {
        let available = screens.compactMap { screen in
            screen.profile.map { (builtIn: screen.isBuiltIn, profile: $0) }
        }
        // Keep fire on the laptop's real notch even when an external display becomes primary.
        // A closed/inactive laptop is excluded; fallback follows the active primary display.
        return available.first { $0.builtIn && $0.profile.notchFrame != nil }?.profile
            ?? available.first { $0.profile.notchFrame != nil }?.profile
            ?? available.first?.profile
    }

    static func frameRate(for maximum: Int) -> Int { maximum > 0 ? min(120, maximum) : 60 }
    var preferredFramesPerSecond: Int { Self.frameRate(for: maximumFramesPerSecond) }

    var anchorFrame: CGRect {
        notchFrame ?? CGRect(x: screenFrame.midX - 90, y: screenFrame.maxY - 32,
            width: 180, height: 32)
    }

    var geometry: NotchFlameGeometry {
        NotchFlameGeometry(notchWidth: anchorFrame.width, notchHeight: anchorFrame.height)
    }

    var panelFrame: CGRect {
        CGRect(x: anchorFrame.midX - geometry.size.width / 2,
            y: anchorFrame.maxY - geometry.size.height,
            width: geometry.size.width, height: geometry.size.height)
    }

    var summary: String {
        let anchor = notchFrame == nil ? "屏幕顶部居中" : "系统刘海"
        return String(format: "%@ · %@ %.1f × %.1f pt · %.0f× · %d fps",
            screenName, anchor, Double(anchorFrame.width), Double(anchorFrame.height),
            Double(scale), preferredFramesPerSecond)
    }
}
