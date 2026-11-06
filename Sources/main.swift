import AppKit
import Foundation

enum Reader {
    static func smctlURL() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("bin/smctl"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        let candidates = [
            FileManager.default.currentDirectoryPath + "/smctl",
            NSString(string: "~/fanlite/bin/smctl").expandingTildeInPath
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        return nil
    }

    static func read(smctl: URL) -> Reading? {
        let process = Process()
        process.executableURL = smctl
        process.arguments = ["sensors", "--json"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let temps = json["temperatures"] as? [[String: Any]] ?? []
        let cpuSamples = temps.compactMap { item -> Double? in
            guard let group = item["group"] as? String,
                  group == "Tp" || group == "TC",
                  let value = item["celsius"] as? Double else { return nil }
            return value
        }
        let cpu = cpuSamples.max()

        let fans = json["fans"] as? [[String: Any]] ?? []
        let fanReadings: [FanReading] = fans.enumerated().map { offset, item in
            FanReading(
                index: (item["index"] as? Int) ?? offset,
                actualRPM: (item["actualRPM"] as? Double) ?? 0,
                targetRPM: (item["targetRPM"] as? Double) ?? 0,
                minRPM: (item["minimumRPM"] as? Double) ?? 0,
                maxRPM: (item["maximumRPM"] as? Double) ?? 0,
                mode: (item["mode"] as? String) ?? "unknown"
            )
        }

        let powerItems = json["power"] as? [[String: Any]] ?? []
        let packagePower = powerItems.first { ($0["key"] as? String) == "PDTR" }?["value"] as? Double

        return Reading(cpuTemp: cpu, fans: fanReadings, packagePower: packagePower)
    }
}

final class FanLiteApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusLine = NSMenuItem(title: "讀取中…", action: nil, keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "刷新頻率", action: nil, keyEquivalent: "")
    private let fanItem = NSMenuItem(title: "風扇控制（smctl）", action: nil, keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "開機自動啟動", action: nil, keyEquivalent: "")
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private let openPanelOnLaunch = CommandLine.arguments.contains("--panel")
    private lazy var controlPanel: ControlPanel = ControlPanel(
        onProfile: { [weak self] profile in self?.applyProfile(profile) },
        onManual: { [weak self] index, rpm in self?.applyManual(index: index, rpm: rpm) },
        onAuto: { [weak self] enabled in self?.setAutoEnabled(enabled) },
        onLoginItem: { [weak self] enabled in self?.setLaunchAtLogin(enabled) },
        onInterval: { [weak self] value in self?.setIntervalValue(value) },
        onClose: { NSApp.setActivationPolicy(.accessory) }
    )
    private var policy = ThermalPolicy()
    private var lastAutoTarget: Int?
    private let thermalQueue = DispatchQueue(label: "io.github.boday.fanlite.thermal")
    private var thermalTimer: DispatchSourceTimer?
    private lazy var helperInstalled = FileManager.default.fileExists(
        atPath: "/Library/PrivilegedHelperTools/one.leaper.smctl.daemon"
    )
    private var autoEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "autoThermal") == nil {
                return helperInstalled
            }
            return UserDefaults.standard.bool(forKey: "autoThermal")
        }
        set { UserDefaults.standard.set(newValue, forKey: "autoThermal") }
    }
    private var interval: Double {
        get {
            let v = UserDefaults.standard.double(forKey: "refreshInterval")
            return v > 0 ? v : 10
        }
        set { UserDefaults.standard.set(newValue, forKey: "refreshInterval") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .suddenTerminationDisabled],
            reason: "FanLite menu bar refresh"
        )
        statusItem.button?.title = "🌡 --° | -- RPM"
        buildMenu()
        refresh()
        scheduleTimer()
        startThermalMonitoring()
        if openPanelOnLaunch {
            openPanel()
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        let open = NSMenuItem(title: "開啟控制面板…", action: #selector(openPanel), keyEquivalent: ",")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        let refreshMenu = NSMenu()
        for seconds in [5.0, 10.0, 30.0, 60.0] {
            let item = NSMenuItem(title: "\(Int(seconds)) 秒", action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            item.state = (seconds == interval) ? .on : .off
            refreshMenu.addItem(item)
        }
        refreshItem.submenu = refreshMenu
        menu.addItem(refreshItem)

        let fanMenu = NSMenu()
        for (title, profile) in [("自動（macOS 控制）", "auto"), ("安靜", "quiet"), ("全速", "full")] {
            let item = NSMenuItem(title: title, action: #selector(setFanProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile
            fanMenu.addItem(item)
        }
        fanItem.submenu = fanMenu
        menu.addItem(fanItem)

        launchAtLoginItem.target = self
        launchAtLoginItem.action = #selector(toggleLaunchAtLogin(_:))
        launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "結束 FanLite", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func tick() { refresh() }

    @objc private func openPanel() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        controlPanel.show()
        if let reading = currentReading {
            controlPanel.update(
                reading: reading,
                interval: interval,
                autoEnabled: autoEnabled,
                launchAtLoginEnabled: LaunchAtLogin.isEnabled
            )
        }
    }

    private var currentReading: Reading?

    private func refresh() {
        guard let smctl = Reader.smctlURL(), let reading = Reader.read(smctl: smctl) else {
            statusItem.button?.title = "🌡 讀取失敗"
            statusLine.title = "無法讀取 smctl sensors --json"
            return
        }
        currentReading = reading
        let temp = reading.cpuTemp.map { String(format: "%.0f°C", $0) } ?? "--"
        let rpm = reading.fans.map { String(format: "%.0f", $0.actualRPM) }.joined(separator: "/")
        statusItem.button?.title = "🌡 \(temp) | \(rpm.isEmpty ? "--" : rpm) RPM"
        let power = reading.packagePower.map { String(format: "%.1fW", $0) } ?? "--"
        statusLine.title = "CPU 最高 \(temp)｜風扇 \(rpm.isEmpty ? "--" : rpm) RPM｜封裝 \(power)"
        controlPanel.update(
            reading: reading,
            interval: interval,
            autoEnabled: autoEnabled,
            launchAtLoginEnabled: LaunchAtLogin.isEnabled
        )
        writeLog("cpu=\(temp) fans=\(rpm.isEmpty ? "--" : rpm) package=\(power)")
    }

    /// 溫控判斷與 UI 刷新脫鉤：UI 預設 10 秒，但熱控制每 2 秒取樣，
    /// 避免 80°C 的短暫尖峰被 10 秒輪詢漏掉。
    private func startThermalMonitoring() {
        thermalTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: thermalQueue)
        timer.schedule(deadline: .now() + 1, repeating: 2.0)
        timer.setEventHandler { [weak self] in self?.thermalTick() }
        timer.resume()
        thermalTimer = timer
    }

    private func thermalTick() {
        guard autoEnabled,
              let smctl = Reader.smctlURL(),
              let reading = Reader.read(smctl: smctl),
              let temperature = reading.cpuTemp else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.autoEnabled else { return }
            let target = self.policy.target(for: temperature)
            guard target != self.lastAutoTarget else { return }
            self.lastAutoTarget = target
            self.writeLog("thermal=\(String(format: "%.1f", temperature))C target=\(target)")
            self.applyAutoTarget(target, fans: reading.fans)
        }
    }

    private func writeLog(_ message: String) {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("FanLite.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber, size.intValue > 256 * 1024 {
            try? fm.removeItem(at: url)
        }
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        setIntervalValue(value)
    }

    private func setIntervalValue(_ value: Double) {
        interval = value
        for item in (refreshItem.submenu?.items ?? []) {
            item.state = (item.representedObject as? Double) == value ? .on : .off
        }
        scheduleTimer()
        refresh()
    }

    @objc private func setFanProfile(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? String else { return }
        applyProfile(profile)
    }

    private func applyProfile(_ profile: String) {
        autoEnabled = false
        lastAutoTarget = nil
        runSMCTL(["fan", "profile", profile], failureTitle: "無法切換風扇模式")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
    }

    private func setAutoEnabled(_ enabled: Bool) {
        autoEnabled = enabled
        policy = ThermalPolicy()
        lastAutoTarget = nil
        refresh()
        if enabled {
            thermalQueue.async { [weak self] in self?.thermalTick() }
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        setLaunchAtLogin(sender.state != .on)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginItem.state = enabled ? .on : .off
            writeLog("login-item=\(enabled ? "enabled" : "disabled")")
        } catch {
            launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
            showError(title: "無法設定開機自動啟動", message: error.localizedDescription)
        }
        refresh()
    }

    private func applyAutoTarget(_ target: Int, fans: [FanReading]) {
        guard target > 0 else { return }
        for fan in fans {
            let rpm = min(target, Int(fan.maxRPM))
            runSMCTL(
                ["fan", "set", String(rpm), "--fan", String(fan.index)],
                failureTitle: "自動溫控設定失敗"
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
    }

    private func applyManual(index: Int?, rpm: Int) {
        autoEnabled = false
        lastAutoTarget = nil
        var args = ["fan", "set", String(rpm)]
        if let index {
            args += ["--fan", String(index)]
        }
        runSMCTL(args, failureTitle: "無法設定風扇轉速")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
    }

    @discardableResult
    private func runSMCTL(_ arguments: [String], failureTitle: String) -> Bool {
        guard let smctl = Reader.smctlURL() else {
            showError(title: failureTitle, message: "找不到 smctl")
            return false
        }
        let process = Process()
        process.executableURL = smctl
        process.arguments = arguments
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let data = err.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8) ?? "未知錯誤"
                showError(title: failureTitle, message: message + "\n\n需要先安裝 smctl helper：\nsudo \(smctl.path) daemon install")
                return false
            }
            return true
        } catch {
            showError(title: failureTitle, message: error.localizedDescription)
            return false
        }
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func quit() {
        timer?.invalidate()
        thermalTimer?.cancel()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        NSApp.terminate(nil)
    }
}

if CommandLine.arguments.contains("--login-item-status") {
    print(LaunchAtLogin.isEnabled ? "enabled" : "disabled")
    print(LaunchAtLogin.plistURL.path)
    exit(0)
}

if CommandLine.arguments.contains("--enable-login-item") {
    do {
        try LaunchAtLogin.setEnabled(true)
        print("enabled")
        exit(0)
    } catch {
        fputs("enable login item failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

if CommandLine.arguments.contains("--disable-login-item") {
    do {
        try LaunchAtLogin.setEnabled(false)
        print("disabled")
        exit(0)
    } catch {
        fputs("disable login item failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

if CommandLine.arguments.contains("--policy-test") {
    exit(ThermalPolicy.selfTest() ? 0 : 1)
}

if CommandLine.arguments.contains("--once") {
    guard let smctl = Reader.smctlURL(), let r = Reader.read(smctl: smctl) else {
        fputs("read failed\n", stderr)
        exit(1)
    }
    let temp = r.cpuTemp.map { String(format: "%.1f", $0) } ?? "n/a"
    let fans = r.fans.map { String(format: "%.0f", $0.actualRPM) }.joined(separator: "/")
    let power = r.packagePower.map { String(format: "%.1f", $0) } ?? "n/a"
    print("cpu_max=\(temp)C fans=\(fans)RPM package=\(power)W")
    exit(0)
}

let app = NSApplication.shared
let delegate = FanLiteApp()
app.delegate = delegate
app.run()
