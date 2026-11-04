import AppKit

enum FlamePreviewBackground: CaseIterable {
    case dark, white, multicolor
    var title: String {
        switch self {
        case .dark: "深色背景"
        case .white: "纯白背景"
        case .multicolor: "多色背景"
        }
    }
    @MainActor func draw(in rect: CGRect) {
        switch self {
        case .dark:
            NSColor(srgbRed: 0.045, green: 0.055, blue: 0.08, alpha: 1).setFill()
            rect.fill()
        case .white:
            NSColor.white.setFill()
            rect.fill()
        case .multicolor:
            let colors: [NSColor] = [
                NSColor(srgbRed: 0.90, green: 0.75, blue: 0.37, alpha: 1),
                NSColor(srgbRed: 0.16, green: 0.32, blue: 0.48, alpha: 1),
                NSColor(srgbRed: 0.44, green: 0.78, blue: 0.70, alpha: 1),
                NSColor(srgbRed: 0.76, green: 0.32, blue: 0.42, alpha: 1),
            ]
            for row in 0...Int(rect.height / 24) {
                for column in 0...Int(rect.width / 32) {
                    colors[(row + column) % colors.count].setFill()
                    CGRect(x: rect.minX + CGFloat(column * 32), y: rect.minY + CGFloat(row * 24),
                        width: 32, height: 24).intersection(rect).fill()
                }
            }
        }
    }
}

@MainActor
private final class FlamePreviewScene: NSView {
    let flame: NotchFlameMetalView
    let background: FlamePreviewBackground
    override var isFlipped: Bool { true }

    init(geometry: NotchFlameGeometry, renderer: NotchFlameRenderer, background: FlamePreviewBackground) throws {
        self.background = background
        flame = try NotchFlameMetalView(geometry: geometry, renderer: renderer)
        super.init(frame: CGRect(x: 0, y: 0, width: 280, height: 132))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        addSubview(flame)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 280).isActive = true
        heightAnchor.constraint(equalToConstant: 132).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(geometry: NotchFlameGeometry) {
        flame.geometry = geometry
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let size = flame.geometry.size
        let scale = min(1,(bounds.width-24)/size.width,(bounds.height-12)/size.height)
        flame.frame = CGRect(x: (bounds.width-size.width*scale)/2, y: 0,
            width: size.width*scale, height: size.height*scale)
    }

    override func draw(_ dirtyRect: NSRect) {
        background.draw(in: bounds)
        let geometry = flame.geometry
        let scale = flame.frame.width/geometry.size.width
        let notch = CGRect(x: flame.frame.minX+geometry.notch.minX*scale, y: -8,
            width: geometry.notchWidth*scale, height: geometry.notchHeight*scale+8)
        NSColor.black.setFill()
        NSBezierPath(roundedRect: notch, xRadius: geometry.cornerRadius*scale,
            yRadius: geometry.cornerRadius*scale).fill()
    }
}

@MainActor
final class NotchFlamePreviewController: NSWindowController, NSWindowDelegate {
    private let speed = NSSlider(value: 180, minValue: 0, maxValue: 180, target: nil, action: nil)
    private let speedLabel = NSTextField(labelWithString: "")
    private let deviceLabel = NSTextField(labelWithString: "")
    private var scenes: [FlamePreviewScene] = []
    private var screenObserver: NSObjectProtocol?
    private var rates: [Double] = []
    private let presets = NSStackView()
    private let settings: NotchFlameSettings
    var onClose: (() -> Void)?
    private var paletteEditor: NotchFlamePaletteEditor?
    private var previewPalette: NotchFlamePalette?

    init(settings: NotchFlameSettings = .shared, renderer: NotchFlameRenderer? = nil) throws {
        self.settings = settings
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 920, height: 640),
            styleMask: [.titled,.closable,.miniaturizable], backing: .buffered, defer: false)
        window.title = "EmberCat · 火焰设置与预览"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        try buildContent(renderer: renderer ?? NotchFlameRenderer())
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func showWindow(_ sender: Any?) {
        let wasVisible = window?.isVisible == true
        super.showWindow(sender)
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshGeometry() }
            }
        }
        refreshGeometry()
        if !wasVisible { paletteEditor?.reload() }
        changeSpeed()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        for scene in scenes { scene.flame.stop() }
        paletteEditor?.deactivateColors()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        onClose?()
    }

    func deactivateColorWells() { paletteEditor?.deactivateColors() }

    private var geometry: NotchFlameGeometry {
        NotchDisplayProfile.current()?.geometry ?? NotchFlameGeometry(notchWidth: 180, notchHeight: 32)
    }

    private func buildContent(renderer: NotchFlameRenderer) throws {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "刘海流焰")
        title.font = .systemFont(ofSize: 25, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "滑动调整火焰质感，为不同速度设定自己的颜色。")
        subtitle.textColor = .secondaryLabelColor
        deviceLabel.font = .systemFont(ofSize: 12)
        deviceLabel.textColor = .secondaryLabelColor
        scenes = try FlamePreviewBackground.allCases.map {
            try FlamePreviewScene(geometry: geometry, renderer: renderer, background: $0)
        }
        let boxes = scenes.map { scene -> NSStackView in
            let caption = NSTextField(labelWithString: scene.background.title)
            caption.font = .systemFont(ofSize: 12)
            caption.textColor = .secondaryLabelColor
            let box = NSStackView(views: [scene,caption])
            box.orientation = .vertical
            box.spacing = 8
            return box
        }
        let samples = NSStackView(views: boxes)
        samples.spacing = 12
        speed.target = self
        speed.isContinuous = true
        speed.action = #selector(changeSpeed)
        speed.setAccessibilityIdentifier("flame-preview-speed")
        speed.setAccessibilityLabel("模拟输出速度")
        speed.widthAnchor.constraint(equalToConstant: 610).isActive = true
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        let speedRow = NSStackView(views: [speedLabel,speed])
        speedRow.spacing = 20
        presets.spacing = 8
        let editor = NotchFlamePaletteEditor(settings: settings)
        paletteEditor = editor
        editor.onPreviewChange = { [weak self] in self?.previewConfiguration(palette: $0, appearance: $1) }
        let hint = NSTextField(labelWithString: "此窗口使用模拟 tok/s；顶部火焰和菜单栏继续读取真实输出。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title,subtitle,deviceLabel,samples,speedRow,presets,editor,hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor,constant: 20)])
        previewConfiguration(palette: settings.palette, appearance: settings.appearance)
        refreshGeometry()
    }

    @objc private func changeSpeed() {
        speedLabel.stringValue = String(format: "预览 · %.0f tok/s",speed.doubleValue)
        for scene in scenes { scene.flame.setSpeed(speed.doubleValue, active: speed.doubleValue>0) }
    }

    @objc private func selectRate(_ sender: NSButton) {
        guard rates.indices.contains(sender.tag) else { return }
        speed.doubleValue = rates[sender.tag]
        changeSpeed()
    }

    private func previewConfiguration(palette: NotchFlamePalette, appearance: NotchFlameAppearance) {
        for scene in scenes {
            scene.flame.setPalette(palette)
            scene.flame.setAppearance(appearance)
        }
        guard palette != previewPalette else { return }
        previewPalette = palette
        speed.maxValue = palette.previewMaximum
        speed.doubleValue = min(speed.doubleValue, speed.maxValue)
        rates = palette.sampleRates
        for view in presets.arrangedSubviews { presets.removeArrangedSubview(view); view.removeFromSuperview() }
        for (index, rate) in rates.enumerated() {
            let title = index == 0 ? "0 · 熄灭" : "第 \(index) 档 · \(Int(rate.rounded()))"
            let button = NSButton(title: title, target: self, action: #selector(selectRate(_:)))
            button.tag = index
            button.controlSize = .small
            button.widthAnchor.constraint(equalToConstant: min(180, 820 / CGFloat(rates.count))).isActive = true
            button.setAccessibilityIdentifier("flame-preview-band-\(index)")
            presets.addArrangedSubview(button)
        }
        changeSpeed()
    }

    private func refreshGeometry() {
        let geometry = self.geometry
        let profile = NotchDisplayProfile.current()
        deviceLabel.stringValue = (profile?.summary ?? "未检测到显示器")
            + (profile == nil ? " · 以下为示例预览" : " · 自动适配")
        for scene in scenes { scene.update(geometry: geometry) }
        if window?.isVisible == true { changeSpeed() }
    }
}
