import AppKit
import Foundation

struct FanReading {
    let index: Int
    let actualRPM: Double
    let targetRPM: Double
    let minRPM: Double
    let maxRPM: Double
    let mode: String
}

struct Reading {
    var cpuTemp: Double?
    var sensors: [SensorReading] = []
    var fans: [FanReading]
    var packagePower: Double?
}

/// 最近 60 筆溫度（2 秒取樣約 2 分鐘）的簡單折線圖。
private final class HistoryView: NSView {
    static let capacity = 60
    private(set) var samples: [Double] = []

    func append(_ value: Double) {
        samples.append(value)
        if samples.count > Self.capacity { samples.removeFirst() }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        guard samples.count > 1 else { return }
        let low = min(40, samples.min() ?? 40)
        let high = max(100, samples.max() ?? 100)
        let span = max(1, high - low)
        let path = NSBezierPath()
        for (index, sample) in samples.enumerated() {
            let x = bounds.minX + CGFloat(index) / CGFloat(Self.capacity - 1) * bounds.width
            let y = bounds.minY + CGFloat((sample - low) / span) * bounds.height
            if index == 0 { path.move(to: NSPoint(x: x, y: y)) }
            else { path.line(to: NSPoint(x: x, y: y)) }
        }
        NSColor.systemOrange.setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}

final class ControlPanel: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let tempLabel = NSTextField(labelWithString: "--°C")
    private let sensorLabel = NSTextField(labelWithString: "溫度來源：最高溫")
    private let detailLabel = NSTextField(labelWithString: "讀取中…")
    private let profileLabel = NSTextField(labelWithString: "風扇模式：--")
    private let historyView = HistoryView()
    private var fanRows: [(name: NSTextField, rpm: NSTextField, slider: NSSlider)] = []
    private let syncButton = NSButton(checkboxWithTitle: "同步兩顆風扇", target: nil, action: nil)
    private let autoCheckbox = NSButton(checkboxWithTitle: "80°C 自動增壓（可編輯曲線）", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "登入時自動啟動 FanLite", target: nil, action: nil)
    private let refreshPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let intervalValues: [Double] = [5, 10, 30, 60]
    private var latest: Reading?
    private var currentCurve = ThermalCurve.default
    private var curveTempFields: [NSTextField] = []
    private var curveRPMFields: [NSTextField] = []
    private let curveMessage = NSTextField(labelWithString: "")

    private let onProfile: (String) -> Void
    private let onManual: (Int?, Int) -> Void
    private let onAuto: (Bool) -> Void
    private let onCurve: (ThermalCurve) -> Void
    private let onLoginItem: (Bool) -> Void
    private let onInterval: (Double) -> Void
    private let onClose: () -> Void

    init(
        onProfile: @escaping (String) -> Void,
        onManual: @escaping (Int?, Int) -> Void,
        onAuto: @escaping (Bool) -> Void,
        onCurve: @escaping (ThermalCurve) -> Void,
        onLoginItem: @escaping (Bool) -> Void,
        onInterval: @escaping (Double) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onProfile = onProfile
        self.onManual = onManual
        self.onAuto = onAuto
        self.onCurve = onCurve
        self.onLoginItem = onLoginItem
        self.onInterval = onInterval
        self.onClose = onClose
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 880),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "FanLite 風扇控制"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("FanLiteControlPanel")
        buildUI()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func update(
        reading: Reading,
        interval: Double,
        autoEnabled: Bool,
        launchAtLoginEnabled: Bool,
        temperature: Double?,
        sensorName: String,
        curve: ThermalCurve
    ) {
        latest = reading
        autoCheckbox.state = autoEnabled ? .on : .off
        loginCheckbox.state = launchAtLoginEnabled ? .on : .off
        let temp = temperature.map { String(format: "%.1f°C", $0) } ?? "--"
        tempLabel.stringValue = temp
        sensorLabel.stringValue = "溫度來源：\(sensorName)"
        if let temperature { historyView.append(temperature) }

        let fans = reading.fans
        let rpmText = fans.map { String(format: "Fan %d  %.0f RPM", $0.index, $0.actualRPM) }
            .joined(separator: " ｜ ")
        let power = reading.packagePower.map { String(format: "%.1f W", $0) } ?? "--"
        detailLabel.stringValue = "\(rpmText) ｜ 封裝 \(power)"

        let mode = fans.first?.mode ?? "--"
        profileLabel.stringValue = "風扇模式：\(mode.uppercased())"

        let pressed = NSEvent.pressedMouseButtons != 0
        for (i, fan) in fans.prefix(fanRows.count).enumerated() {
            let row = fanRows[i]
            row.name.stringValue = "Fan \(fan.index)"
            row.rpm.stringValue = String(format: "%.0f RPM", fan.actualRPM)
            row.slider.minValue = fan.minRPM
            row.slider.maxValue = fan.maxRPM
            row.slider.isEnabled = true
            if !pressed {
                row.slider.doubleValue = fan.targetRPM > 0 ? fan.targetRPM : fan.actualRPM
            }
        }

        if currentCurve != curve {
            currentCurve = curve
            applyCurveToFields(curve)
        }
        if let idx = intervalValues.firstIndex(where: { abs($0 - interval) < 0.01 }) {
            refreshPopup.selectItem(at: idx)
        }
    }

    private func applyCurveToFields(_ curve: ThermalCurve) {
        let values = [curve.warmEnter, curve.hotEnter, curve.criticalEnter]
        for (i, field) in curveTempFields.enumerated() where i < values.count {
            field.stringValue = String(format: "%.0f", values[i])
        }
        let rpms = [curve.normalRPM, curve.warmRPM, curve.hotRPM, curve.criticalRPM]
        for (i, field) in curveRPMFields.enumerated() where i < rpms.count {
            field.stringValue = String(rpms[i])
        }
    }

    private func buildUI() {
        guard let content = window.contentView else { return }
        content.wantsLayer = true

        tempLabel.font = .systemFont(ofSize: 44, weight: .bold)
        tempLabel.textColor = .labelColor
        tempLabel.alignment = .center

        sensorLabel.font = .systemFont(ofSize: 11)
        sensorLabel.textColor = .secondaryLabelColor
        sensorLabel.alignment = .center

        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.lineBreakMode = .byTruncatingTail

        profileLabel.font = .systemFont(ofSize: 12, weight: .medium)
        profileLabel.textColor = .secondaryLabelColor
        profileLabel.alignment = .center

        historyView.frame = NSRect(x: 0, y: 0, width: 400, height: 72)
        NSLayoutConstraint.activate([
            historyView.heightAnchor.constraint(equalToConstant: 72)
        ])

        let header = NSTextField(labelWithString: "FanLite")
        header.font = .systemFont(ofSize: 22, weight: .semibold)
        header.alignment = .center

        let subtitle = NSTextField(labelWithString: "溫度與雙風扇控制")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center

        var views: [NSView] = [header, subtitle, tempLabel, sensorLabel, historyView, detailLabel, profileLabel]
        views.append(separator())

        for index in 0..<2 {
            let name = NSTextField(labelWithString: "Fan \(index)")
            name.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            let rpm = NSTextField(labelWithString: "-- RPM")
            rpm.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            rpm.textColor = .secondaryLabelColor
            rpm.alignment = .right
            let slider = NSSlider(value: 1200, minValue: 1200, maxValue: 6000, target: self, action: #selector(sliderChanged(_:)))
            slider.tag = index
            slider.isContinuous = false
            slider.isEnabled = false

            let titleRow = NSStackView(views: [name, spacer(), rpm])
            titleRow.orientation = .horizontal
            let row = NSStackView(views: [titleRow, slider])
            row.orientation = .vertical
            row.spacing = 4
            views.append(row)
            fanRows.append((name, rpm, slider))
        }

        syncButton.state = .off
        views.append(syncButton)

        autoCheckbox.state = .on
        autoCheckbox.target = self
        autoCheckbox.action = #selector(autoChanged)
        views.append(autoCheckbox)

        loginCheckbox.state = .off
        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginItemChanged)
        views.append(loginCheckbox)

        views.append(separator())
        views.append(curveSection())

        let auto = makeButton("系統自動", action: #selector(profileAuto))
        let daily = makeButton("日常 3000", action: #selector(profileDaily))
        let quiet = makeButton("安靜", action: #selector(profileQuiet))
        let full = makeButton("全速", action: #selector(profileFull))
        let buttons = NSStackView(views: [auto, daily, quiet, full])
        buttons.orientation = .horizontal
        buttons.spacing = 6
        buttons.distribution = .fillEqually
        views.append(buttons)

        let refreshLabel = NSTextField(labelWithString: "刷新頻率")
        refreshLabel.font = .systemFont(ofSize: 12)
        refreshLabel.textColor = .secondaryLabelColor
        for value in intervalValues {
            refreshPopup.addItem(withTitle: "\(Int(value)) 秒")
        }
        refreshPopup.target = self
        refreshPopup.action = #selector(refreshChanged)
        let refreshRow = NSStackView(views: [refreshLabel, spacer(), refreshPopup])
        refreshRow.orientation = .horizontal
        views.append(refreshRow)

        let note = NSTextField(wrappingLabelWithString: "風扇控制由 smctl root helper 提供。拉動滑桿會立即套用；結束 FanLite 前可先按「自動」交還 macOS。")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        views.append(note)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        applyCurveToFields(currentCurve)
    }

    private func curveSection() -> NSView {
        let title = NSTextField(labelWithString: "風扇曲線（進階）")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        let header = NSTextField(labelWithString: "進入 °C（暖／高／臨界）")
        header.font = .systemFont(ofSize: 11)
        header.textColor = .secondaryLabelColor
        let temps = NSStackView()
        temps.orientation = .horizontal
        temps.distribution = .fillEqually
        temps.spacing = 6
        for _ in 0..<3 {
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 22))
            field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            curveTempFields.append(field)
            temps.addArrangedSubview(field)
        }

        let rpmHeader = NSTextField(labelWithString: "目標 RPM（日常／暖／高／臨界）")
        rpmHeader.font = .systemFont(ofSize: 11)
        rpmHeader.textColor = .secondaryLabelColor
        let rpms = NSStackView()
        rpms.orientation = .horizontal
        rpms.distribution = .fillEqually
        rpms.spacing = 6
        for _ in 0..<4 {
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 22))
            field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            curveRPMFields.append(field)
            rpms.addArrangedSubview(field)
        }

        let apply = makeButton("套用曲線", action: #selector(applyCurve))
        let reset = makeButton("重置", action: #selector(resetCurve))
        let actions = NSStackView(views: [apply, reset])
        actions.orientation = .horizontal
        actions.spacing = 6
        actions.distribution = .fillEqually

        curveMessage.font = .systemFont(ofSize: 11)
        curveMessage.textColor = .systemRed

        let stack = NSStackView(views: [title, header, temps, rpmHeader, rpms, actions, curveMessage])
        stack.orientation = .vertical
        stack.spacing = 6
        return stack
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func spacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return v
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        return button
    }

    @objc private func applyCurve() {
        guard curveTempFields.count == 3, curveRPMFields.count == 4 else { return }
        let w = Double(curveTempFields[0].stringValue) ?? .nan
        let h = Double(curveTempFields[1].stringValue) ?? .nan
        let c = Double(curveTempFields[2].stringValue) ?? .nan
        let n = Int(curveRPMFields[0].stringValue) ?? -1
        let wr = Int(curveRPMFields[1].stringValue) ?? -1
        let hr = Int(curveRPMFields[2].stringValue) ?? -1
        let cr = Int(curveRPMFields[3].stringValue) ?? -1
        let candidate = ThermalCurve(
            warmEnter: w, hotEnter: h, criticalEnter: c,
            warmExit: min(currentCurve.warmExit, w - 5),
            hotExit: min(currentCurve.hotExit, h - 5),
            criticalExit: min(currentCurve.criticalExit, c - 5),
            normalRPM: n, warmRPM: wr, hotRPM: hr, criticalRPM: cr,
            minimumDwell: currentCurve.minimumDwell
        )
        guard candidate.isValid else {
            curveMessage.stringValue = "曲線無效：溫度需遞增、RPM 不可遞減"
            return
        }
        curveMessage.stringValue = ""
        onCurve(candidate)
    }

    @objc private func resetCurve() {
        curveMessage.stringValue = ""
        onCurve(ThermalCurve.default)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let latest, sender.tag < latest.fans.count else { return }
        let rpm = Int(sender.doubleValue.rounded())
        fanRows[sender.tag].rpm.stringValue = "\(rpm) RPM"
        if syncButton.state == .on {
            for (i, row) in fanRows.enumerated() where i != sender.tag {
                let maxRPM = latest.fans[i].maxRPM
                row.slider.doubleValue = min(Double(rpm), maxRPM)
                row.rpm.stringValue = "\(min(rpm, Int(maxRPM))) RPM"
            }
            onManual(nil, rpm)
        } else {
            onManual(sender.tag, rpm)
        }
    }

    @objc private func profileAuto() { onProfile("auto") }
    @objc private func profileDaily() { onManual(nil, 3000) }
    @objc private func profileQuiet() { onProfile("quiet") }
    @objc private func profileFull() { onProfile("full") }

    @objc private func autoChanged() {
        onAuto(autoCheckbox.state == .on)
    }

    @objc private func loginItemChanged() {
        onLoginItem(loginCheckbox.state == .on)
    }

    @objc private func refreshChanged() {
        let index = refreshPopup.indexOfSelectedItem
        guard index >= 0, index < intervalValues.count else { return }
        onInterval(intervalValues[index])
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
