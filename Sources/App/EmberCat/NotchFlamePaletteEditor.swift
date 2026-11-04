import AppKit

@MainActor
private final class FlameBandRow: NSStackView, NSTextFieldDelegate {
    let minimum = NSTextField()
    let upper = NSTextField(labelWithString: "")
    let hex = NSTextField()
    let well = NSColorWell()
    var onChange: (() -> Void)?
    var onRemove: (() -> Void)?

    init(band: NotchFlameBand, index: Int, end: Double?) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 10
        let name = NSTextField(labelWithString: "第 \(index + 1) 档")
        name.widthAnchor.constraint(equalToConstant: 52).isActive = true
        minimum.stringValue = Self.rate(band.minimumSpeed)
        minimum.isEnabled = index > 0
        minimum.delegate = self
        minimum.alignment = .right
        minimum.setAccessibilityLabel("第 \(index + 1) 档起点")
        minimum.setAccessibilityIdentifier("flame-band-\(index)-minimum")
        minimum.widthAnchor.constraint(equalToConstant: 76).isActive = true
        upper.widthAnchor.constraint(equalToConstant: 110).isActive = true
        upper.textColor = .secondaryLabelColor
        setUpper(end)
        well.color = band.color
        well.colorWellStyle = .expanded
        well.supportsAlpha = false
        well.target = self
        well.action = #selector(changeColor)
        well.pulldownTarget = self
        well.pulldownAction = #selector(openColorPanel)
        well.widthAnchor.constraint(equalToConstant: 62).isActive = true
        well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        well.setAccessibilityLabel("第 \(index + 1) 档颜色")
        let choose = NSButton(title: "选色…", target: self, action: #selector(openColorPanel))
        choose.controlSize = .small
        choose.setAccessibilityIdentifier("flame-band-\(index)-choose-color")
        hex.stringValue = band.hex
        hex.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        hex.delegate = self
        hex.widthAnchor.constraint(equalToConstant: 100).isActive = true
        hex.setAccessibilityLabel("第 \(index + 1) 档十六进制颜色")
        hex.setAccessibilityIdentifier("flame-band-\(index)-hex")
        let remove = NSButton(title: "移除", target: self, action: #selector(removeBand))
        remove.isEnabled = index > 0
        remove.controlSize = .small
        remove.setAccessibilityIdentifier("flame-band-\(index)-remove")
        let unit = NSTextField(labelWithString: "tok/s")
        unit.textColor = .secondaryLabelColor
        [name, minimum, NSTextField(labelWithString: "至"), upper, unit, well, choose, hex, remove]
            .forEach { addArrangedSubview($0) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var band: NotchFlameBand {
        NotchFlameBand(minimumSpeed: Double(minimum.stringValue.trimmingCharacters(in: .whitespaces)) ?? .nan,
            hex: hex.stringValue.trimmingCharacters(in: .whitespaces).uppercased())
    }

    func setUpper(_ value: Double?) {
        upper.stringValue = value.map { $0.isFinite ? "< \(Self.rate($0))" : "待填写" } ?? "无上限"
    }

    static func rate(_ value: Double) -> String {
        value.rounded() == value ? String(format: "%.0f", value) : String(value)
    }

    func controlTextDidChange(_ obj: Notification) {
        let sample = NotchFlamePalette(bands: [NotchFlameBand(minimumSpeed: 0, hex: band.hex)])
        if sample.validationError == nil { well.color = band.color }
        onChange?()
    }

    @objc private func changeColor() {
        guard let value = NotchFlameBand.hex(for: well.color) else { return }
        hex.stringValue = value
        onChange?()
    }

    @objc private func openColorPanel() {
        NSApp.activate(ignoringOtherApps: true)
        NSColorPanel.shared.title = "火焰颜色"
        NSColorPanel.shared.isContinuous = true
        well.activate(true)
        NSColorPanel.shared.makeKeyAndOrderFront(nil)
    }

    @objc private func removeBand() { onRemove?() }
}

@MainActor
private final class FlameRowsDocument: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class FlameAppearanceControls: NSStackView {
    private var currentAppearance = NotchFlameAppearance.standard
    private var sliders: [NSSlider] = []
    private var values: [NSTextField] = []
    var onChange: ((NotchFlameAppearance) -> Void)?

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 9
        heightAnchor.constraint(equalToConstant: 144).isActive = true
        let hint = NSTextField(labelWithString: "拖动即可预览，数值越大效果越强；通透度越高，越能透出背景。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        addArrangedSubview(hint)
        var row: NSStackView?
        for (index, parameter) in NotchFlameParameter.allCases.enumerated() {
            if index.isMultiple(of: 2) {
                row = NSStackView()
                row?.spacing = 32
                addArrangedSubview(row!)
            }
            let label = NSTextField(labelWithString: parameter.title)
            label.font = .systemFont(ofSize: 12)
            label.widthAnchor.constraint(equalToConstant: 64).isActive = true
            let slider = NSSlider(value: currentAppearance[keyPath: parameter.keyPath],
                minValue: parameter.range.lowerBound, maxValue: parameter.range.upperBound,
                target: self, action: #selector(change(_:)))
            slider.isContinuous = true
            slider.tag = index
            slider.widthAnchor.constraint(equalToConstant: 270).isActive = true
            slider.setAccessibilityLabel(parameter.title)
            slider.setAccessibilityIdentifier("flame-style-\(parameter.rawValue)")
            slider.toolTip = parameter.help
            label.toolTip = parameter.help
            let value = NSTextField(labelWithString: "")
            value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            value.alignment = .right
            value.widthAnchor.constraint(equalToConstant: 48).isActive = true
            let control = NSStackView(views: [label, slider, value])
            control.spacing = 8
            control.heightAnchor.constraint(equalToConstant: 26).isActive = true
            row?.addArrangedSubview(control)
            sliders.append(slider)
            values.append(value)
        }
        reload(.standard)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func reload(_ appearance: NotchFlameAppearance) {
        currentAppearance = appearance
        for (index, parameter) in NotchFlameParameter.allCases.enumerated() {
            sliders[index].doubleValue = appearance[keyPath: parameter.keyPath]
            values[index].stringValue = String(format: "%.0f%%", sliders[index].doubleValue * 100)
        }
    }

    @objc private func change(_ sender: NSSlider) {
        let parameter = NotchFlameParameter.allCases[sender.tag]
        let value = (sender.doubleValue * 100).rounded() / 100
        currentAppearance[keyPath: parameter.keyPath] = value
        sender.doubleValue = value
        values[sender.tag].stringValue = String(format: "%.0f%%", value * 100)
        onChange?(currentAppearance)
    }
}

/// Drafts affect only the previews. A validated save updates the live overlay atomically.
@MainActor
final class NotchFlamePaletteEditor: NSView {
    private let settings: NotchFlameSettings
    private var draft: NotchFlamePalette
    private var appearanceDraft: NotchFlameAppearance
    private var rows: [FlameBandRow] = []
    private let document = FlameRowsDocument()
    private let appearanceControls = FlameAppearanceControls()
    private let paletteControls = NSStackView()
    private let mode = NSSegmentedControl(labels: ["火焰质感", "速度与颜色"],
        trackingMode: .selectOne, target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private let save = NSButton(title: "保存并应用", target: nil, action: nil)
    private let add = NSButton(title: "添加区间", target: nil, action: nil)
    var onPreviewChange: ((NotchFlamePalette, NotchFlameAppearance) -> Void)?

    init(settings: NotchFlameSettings) {
        self.settings = settings
        draft = settings.palette
        appearanceDraft = settings.appearance
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 860).isActive = true
        heightAnchor.constraint(equalToConstant: 230).isActive = true
        mode.selectedSegment = 0
        mode.target = self
        mode.action = #selector(selectSettingsSection)
        mode.setAccessibilityIdentifier("flame-settings-section")
        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetPalette))
        reset.controlSize = .small
        reset.toolTip = "恢复默认质感、颜色和区间；保存后应用。"
        reset.setAccessibilityIdentifier("flame-palette-reset")
        add.target = self
        add.action = #selector(addBand)
        add.controlSize = .small
        add.setAccessibilityIdentifier("flame-palette-add")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [mode, spacer, reset, add])
        header.spacing = 10
        let help = NSTextField(labelWithString: "设置每档起点和颜色，上一档的终点会自动衔接。0 tok/s 熄灭。")
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = document
        scroll.heightAnchor.constraint(equalToConstant: 120).isActive = true
        paletteControls.orientation = .vertical
        paletteControls.alignment = .leading
        paletteControls.spacing = 10
        paletteControls.addArrangedSubview(help)
        paletteControls.addArrangedSubview(scroll)
        paletteControls.heightAnchor.constraint(equalToConstant: 144).isActive = true
        appearanceControls.reload(appearanceDraft)
        appearanceControls.onChange = { [weak self] appearance in
            self?.appearanceDraft = appearance
            self?.edit()
        }
        let body = NSStackView(views: [appearanceControls, paletteControls])
        body.orientation = .vertical
        body.alignment = .leading
        body.detachesHiddenViews = true
        save.target = self
        save.action = #selector(savePalette)
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.setAccessibilityIdentifier("flame-palette-save")
        status.font = .systemFont(ofSize: 12)
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        status.setAccessibilityIdentifier("flame-palette-status")
        let footer = NSStackView(views: [status, save])
        footer.spacing = 12
        let stack = NSStackView(views: [header, body, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        selectSettingsSection()
        rebuildRows()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func reload() {
        draft = settings.palette
        appearanceDraft = settings.appearance
        appearanceControls.reload(appearanceDraft)
        rebuildRows()
    }

    func deactivateColors() {
        let wasActive = rows.contains { $0.well.isActive }
        rows.forEach { $0.well.deactivate() }
        if wasActive { NSColorPanel.shared.orderOut(nil) }
    }

    private func rebuildRows() {
        deactivateColors()
        rows.forEach { $0.removeFromSuperview() }
        rows = draft.bands.indices.map { index in
            let row = FlameBandRow(band: draft.bands[index], index: index,
                end: index + 1 < draft.bands.count ? draft.bands[index + 1].minimumSpeed : nil)
            row.frame = CGRect(x: 0, y: index * 38, width: 820, height: 34)
            row.onChange = { [weak self] in self?.edit() }
            row.onRemove = { [weak self] in
                guard let self, index > 0, index < draft.bands.count else { return }
                draft.bands.remove(at: index)
                rebuildRows()
            }
            document.addSubview(row)
            return row
        }
        document.frame = CGRect(x: 0, y: 0, width: 840, height: max(120, rows.count * 38))
        edit()
    }

    private func edit() {
        draft = NotchFlamePalette(bands: rows.map(\.band))
        for index in rows.indices {
            rows[index].setUpper(index + 1 < rows.count ? draft.bands[index + 1].minimumSpeed : nil)
        }
        let error = draft.validationError ?? appearanceDraft.validationError
        let changed = draft != settings.palette || appearanceDraft != settings.appearance
        save.isEnabled = error == nil && changed
        add.isEnabled = error == nil && rows.count < NotchFlamePalette.maximumBands
            && (draft.bands.last?.minimumSpeed ?? 0) < 100_000
        status.textColor = error == nil ? .secondaryLabelColor : .systemRed
        status.stringValue = error ?? (!changed ? "已保存 · 顶部火焰使用这些设置"
            : "预览已更新 · 保存后应用到顶部火焰")
        if error == nil { onPreviewChange?(draft, appearanceDraft) }
    }

    @objc private func selectSettingsSection() {
        let colors = mode.selectedSegment == 1
        appearanceControls.isHidden = colors
        paletteControls.isHidden = !colors
        add.isHidden = !colors
        if !colors { deactivateColors() }
    }

    @objc private func addBand() {
        guard draft.validationError == nil, draft.bands.count < NotchFlamePalette.maximumBands else { return }
        let lower = draft.bands.last?.minimumSpeed ?? 0
        guard lower < 100_000 else { return }
        draft.bands.append(NotchFlameBand(minimumSpeed: min(100_000, lower + 60), hex: "#C17BFF"))
        rebuildRows()
        document.scroll(NSPoint(x: 0, y: max(0, document.frame.height - 120)))
    }

    @objc private func resetPalette() {
        draft = .standard
        appearanceDraft = .standard
        appearanceControls.reload(appearanceDraft)
        rebuildRows()
    }

    @objc private func savePalette() {
        window?.makeFirstResponder(nil)
        guard settings.setConfiguration(palette: draft, appearance: appearanceDraft) else { edit(); return }
        draft = settings.palette
        appearanceDraft = settings.appearance
        edit()
    }
}
