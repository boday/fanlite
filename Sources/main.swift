import AppKit
import Foundation

struct Reading {
    var cpuTemp: Double?
    var fanRPMs: [Double]
    var packagePower: Double?
}

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
        let rpms = fans.compactMap { $0["actualRPM"] as? Double }

        let powerItems = json["power"] as? [[String: Any]] ?? []
        let packagePower = powerItems.first { ($0["key"] as? String) == "PDTR" }?["value"] as? Double

        return Reading(cpuTemp: cpu, fanRPMs: rpms, packagePower: packagePower)
    }
}

final class FanLiteApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusLine = NSMenuItem(title: "讀取中…", action: nil, keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "刷新頻率", action: nil, keyEquivalent: "")
    private let fanItem = NSMenuItem(title: "風扇控制（smctl）", action: nil, keyEquivalent: "")
    private var timer: Timer?
    private var activity: NSObjectProtocol?
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
    }

    private func buildMenu() {
        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
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

    private func refresh() {
        guard let smctl = Reader.smctlURL(), let reading = Reader.read(smctl: smctl) else {
            statusItem.button?.title = "🌡 讀取失敗"
            statusLine.title = "無法讀取 smctl sensors --json"
            return
        }
        let temp = reading.cpuTemp.map { String(format: "%.0f°C", $0) } ?? "--"
        let rpm = reading.fanRPMs.map { String(format: "%.0f", $0) }.joined(separator: "/")
        statusItem.button?.title = "🌡 \(temp) | \(rpm.isEmpty ? "--" : rpm) RPM"
        let power = reading.packagePower.map { String(format: "%.1fW", $0) } ?? "--"
        statusLine.title = "CPU 最高 \(temp)｜風扇 \(rpm.isEmpty ? "--" : rpm) RPM｜封裝 \(power)"
        writeLog("cpu=\(temp) fans=\(rpm.isEmpty ? "--" : rpm) package=\(power)")
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
        interval = value
        for item in (refreshItem.submenu?.items ?? []) {
            item.state = (item.representedObject as? Double) == value ? .on : .off
        }
        scheduleTimer()
        refresh()
    }

    @objc private func setFanProfile(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? String,
              let smctl = Reader.smctlURL() else { return }
        let process = Process()
        process.executableURL = smctl
        process.arguments = ["fan", "profile", profile]
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let data = err.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8) ?? "未知錯誤"
                let alert = NSAlert()
                alert.messageText = "無法切換風扇模式"
                alert.informativeText = message + "\n\n需要先安裝 smctl 的 root helper：\nsudo \(smctl.path) daemon install"
                alert.runModal()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "無法執行 smctl"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refresh()
    }

    @objc private func quit() {
        timer?.invalidate()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        NSApp.terminate(nil)
    }
}

if CommandLine.arguments.contains("--once") {
    guard let smctl = Reader.smctlURL(), let r = Reader.read(smctl: smctl) else {
        fputs("read failed\n", stderr)
        exit(1)
    }
    let temp = r.cpuTemp.map { String(format: "%.1f", $0) } ?? "n/a"
    let fans = r.fanRPMs.map { String(format: "%.0f", $0) }.joined(separator: "/")
    let power = r.packagePower.map { String(format: "%.1f", $0) } ?? "n/a"
    print("cpu_max=\(temp)C fans=\(fans)RPM package=\(power)W")
    exit(0)
}

let app = NSApplication.shared
let delegate = FanLiteApp()
app.delegate = delegate
app.run()
