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
    var fans: [FanReading]
    var packagePower: Double?
}

final class ControlPanel: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let tempLabel = NSTextField(labelWithString: "--°C")
    private let detailLabel = NSTextField(labelWithString: "讀取中…")
    private let profileLabel = NSTextField(labelWithString: "風扇模式：--")
    private var fanRows: [(name: NSTextField, rpm: NSTextField, slider: NSSlider)] = []
    private let syncButton = NSButton(checkboxWithTitle: "同步兩顆風扇", target: nil, action: nil)
    private let autoCheckbox = NSButton(checkboxWithTitle: "80°C 自動增壓（最高 6,000 RPM）", target: nil, action: nil)
    private let refreshPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let intervalValues: [Double] = [5, 10, 30, 60]
    private var latest: Reading?

    private let onProfile: (String) -> Void
    private let onManual: (Int?, Int) -> Void
    private let onAuto: (Bool) -> Void
    private let onInterval: (Double) -> Void
    private let onClose: () -> Void

    init(
        onProfile: @escaping (String) -> Void,
        onManual: @escaping (Int?, Int) -> Void,
        onAuto: @escaping (Bool) -> Void,
        onInterval: @escaping (Double) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onProfile = onProfile
        self.onManual = onManual
        self.onAuto = onAuto
        self.onInterval = onInterval
        self.onClose = onClose
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 530),
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

    func update(reading: Reading, interval: Double, autoEnabled: Bool) {
        latest = reading
        autoCheckbox.state = autoEnabled ? .on : .off
        let temp = reading.cpuTemp.map { String(format: "%.1f°C", $0) } ?? "--"
        tempLabel.stringValue = temp

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

        if let idx = intervalValues.firstIndex(where: { abs($0 - interval) < 0.01 }) {
            refreshPopup.selectItem(at: idx)
        }
    }

    private func buildUI() {
        guard let content = window.contentView else { return }
        content.wantsLayer = true

        tempLabel.font = .systemFont(ofSize: 44, weight: .bold)
        tempLabel.textColor = .labelColor
        tempLabel.alignment = .center

        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.lineBreakMode = .byTruncatingTail

        profileLabel.font = .systemFont(ofSize: 12, weight: .medium)
        profileLabel.textColor = .secondaryLabelColor
        profileLabel.alignment = .center

        let header = NSTextField(labelWithString: "FanLite")
        header.font = .systemFont(ofSize: 22, weight: .semibold)
        header.alignment = .center

        let subtitle = NSTextField(labelWithString: "溫度與雙風扇控制")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center

        var views: [NSView] = [header, subtitle, tempLabel, detailLabel, profileLabel]
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

    @objc private func refreshChanged() {
        let index = refreshPopup.indexOfSelectedItem
        guard index >= 0, index < intervalValues.count else { return }
        onInterval(intervalValues[index])
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
