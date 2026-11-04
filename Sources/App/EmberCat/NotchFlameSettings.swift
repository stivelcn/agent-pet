import AppKit
import AgentPetCore

struct NotchFlameAppearance: Codable, Equatable {
    static let standard = NotchFlameAppearance()
    var brightness: Double = 1
    var core: Double = 0.5
    var transparency: Double = 0.4
    var length: Double = 1
    var turbulence: Double = 1
    var flow: Double = 1

    var validationError: String? {
        for parameter in NotchFlameParameter.allCases {
            let value = self[keyPath: parameter.keyPath]
            if !value.isFinite || !parameter.range.contains(value) {
                return "\(parameter.title)超出可调范围。"
            }
        }
        return nil
    }
}

enum NotchFlameParameter: String, CaseIterable {
    case brightness, core, transparency, length, turbulence, flow

    var title: String {
        switch self {
        case .brightness: "亮度"
        case .core: "亮芯范围"
        case .transparency: "通透度"
        case .length: "焰尾长度"
        case .turbulence: "扰动"
        case .flow: "流速"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .brightness: 0.4...1.8
        case .core, .transparency: 0...1
        case .length: 0.35...1.35
        case .turbulence: 0...2
        case .flow: 0.25...2.5
        }
    }

    var keyPath: WritableKeyPath<NotchFlameAppearance, Double> {
        switch self {
        case .brightness: \.brightness
        case .core: \.core
        case .transparency: \.transparency
        case .length: \.length
        case .turbulence: \.turbulence
        case .flow: \.flow
        }
    }

    var help: String {
        switch self {
        case .brightness: "调整火焰主体的明亮程度，描边保持清晰。"
        case .core: "向右增加高亮焰芯的面积，向左保留更多主色。"
        case .transparency: "向右让背景透过火焰，向左增加火焰厚度。"
        case .length: "缩短或拉长向下的焰尾，100% 为默认长度。"
        case .turbulence: "向右增加火焰卷曲和细节变化，向左让流动更平缓。"
        case .flow: "调整流动快慢，100% 为默认速度；仍随真实 tok/s 变化。"
        }
    }
}

struct NotchFlameBand: Codable, Equatable {
    var minimumSpeed: Double
    var hex: String

    var rgb: SIMD3<Float> {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return SIMD3(Float((value >> 16) & 255), Float((value >> 8) & 255), Float(value & 255)) / 255
    }

    var color: NSColor {
        NSColor(srgbRed: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1)
    }

    static func hex(for color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        guard components.allSatisfy(\.isFinite) else { return nil }
        let bytes = components.map { Int((min(1, max(0, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }
}

/// Left-closed, right-open speed bands. The final band has no upper limit.
struct NotchFlamePalette: Codable, Equatable {
    static let maximumBands = 8
    static let standard = NotchFlamePalette(bands: [
        NotchFlameBand(minimumSpeed: 0, hex: "#FFB52E"),
        NotchFlameBand(minimumSpeed: 60, hex: "#FF492E"),
        NotchFlameBand(minimumSpeed: 140, hex: "#4DADFF"),
    ])
    var bands: [NotchFlameBand]

    var validationError: String? {
        guard (1...Self.maximumBands).contains(bands.count) else { return "请保留 1–8 个颜色区间。" }
        guard bands.first?.minimumSpeed == 0 else { return "第一个区间必须从 0 开始。" }
        for (index, band) in bands.enumerated() {
            guard band.minimumSpeed.isFinite, (0...100_000).contains(band.minimumSpeed) else {
                return "第 \(index + 1) 档的起点需为 0–100000 之间的数字。"
            }
            if index > 0, band.minimumSpeed <= bands[index - 1].minimumSpeed {
                return "第 \(index + 1) 档的起点必须大于上一档；区间按起点递增。"
            }
            guard band.hex.count == 7, band.hex.first == "#",
                  band.hex.dropFirst().allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
                return "第 \(index + 1) 档的颜色需为 #RRGGBB，例如 #FF492E。"
            }
        }
        return nil
    }

    func color(for speed: Double) -> SIMD3<Float> {
        let rate = speed.isFinite ? max(0, speed) : 0
        return (bands.last(where: { rate >= $0.minimumSpeed }) ?? Self.standard.bands[0]).rgb
    }

    var previewMaximum: Double { max(180, (bands.last?.minimumSpeed ?? 0) * 1.25 + 20) }

    var sampleRates: [Double] {
        [0] + bands.indices.map { index in
            let start = bands[index].minimumSpeed
            let end = index + 1 < bands.count ? bands[index + 1].minimumSpeed : previewMaximum
            return (start + end) / 2
        }
    }
}

extension Notification.Name {
    static let emberCatFlameSettingsChanged = Notification.Name("EmberCat.FlameSettingsChanged")
}

@MainActor
final class NotchFlameSettings {
    static let shared = NotchFlameSettings()
    private let defaults: UserDefaults
    private(set) var palette: NotchFlamePalette
    private(set) var appearance: NotchFlameAppearance

    init(defaults: UserDefaults = LocalPreferences.defaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "notchFlamePalette"),
           let saved = try? JSONDecoder().decode(NotchFlamePalette.self, from: data),
           saved.validationError == nil {
            palette = saved
        } else {
            palette = .standard
        }
        if let data = defaults.data(forKey: "notchFlameAppearance"),
           let saved = try? JSONDecoder().decode(NotchFlameAppearance.self, from: data),
           saved.validationError == nil {
            appearance = saved
        } else {
            appearance = .standard
        }
    }

    @discardableResult
    func setPalette(_ palette: NotchFlamePalette) -> Bool {
        setConfiguration(palette: palette, appearance: appearance)
    }

    @discardableResult
    func setAppearance(_ appearance: NotchFlameAppearance) -> Bool {
        setConfiguration(palette: palette, appearance: appearance)
    }

    @discardableResult
    func setConfiguration(palette: NotchFlamePalette, appearance: NotchFlameAppearance) -> Bool {
        guard palette.validationError == nil, appearance.validationError == nil else { return false }
        let canonical = NotchFlamePalette(bands: palette.bands.map {
            NotchFlameBand(minimumSpeed: $0.minimumSpeed, hex: $0.hex.uppercased())
        })
        guard let data = try? JSONEncoder().encode(canonical),
              let appearanceData = try? JSONEncoder().encode(appearance) else { return false }
        guard canonical != self.palette || appearance != self.appearance else { return true }
        self.palette = canonical
        self.appearance = appearance
        defaults.set(data, forKey: "notchFlamePalette")
        defaults.set(appearanceData, forKey: "notchFlameAppearance")
        NotificationCenter.default.post(name: .emberCatFlameSettingsChanged, object: self)
        return true
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: "notchFlamesEnabled") as? Bool ?? true }
        set {
            guard newValue != isEnabled else { return }
            defaults.set(newValue, forKey: "notchFlamesEnabled")
            NotificationCenter.default.post(name: .emberCatFlameSettingsChanged, object: self)
        }
    }
}
