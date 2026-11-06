import Foundation

/// 以 per-user LaunchAgent 實作「登入時自動啟動」。
///
/// 選擇 LaunchAgent 而不是 SMAppService 的原因：
/// - FanLite 目前是 ad-hoc 簽章、安裝在 `~/Applications`
/// - LaunchAgent 可用 `launchctl` 直接驗證，行為確定、可腳本化
/// - 不需要 Apple Developer ID 或公證即可運作
enum LaunchAtLogin {
    static let label = "io.github.boday.fanlite"

    private static let fileManager = FileManager.default

    static var plistURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    /// 只有當 plist 存在，且指向目前這份 App 的執行檔時才算啟用。
    /// 若 App 被搬移，舊路徑會被視為未啟用，使用者重新勾選即可修復。
    static var isEnabled: Bool {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String],
              let configured = arguments.first,
              let current = Bundle.main.executableURL?.resolvingSymlinksInPath().path
        else {
            return false
        }
        let configuredPath = URL(fileURLWithPath: configured).resolvingSymlinksInPath().path
        return configuredPath == current
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try install()
        } else {
            try remove()
        }
    }

    private static func install() throws {
        guard let executable = Bundle.main.executableURL else {
            throw NSError(
                domain: label,
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "找不到 FanLite 執行檔路徑"]
            )
        }

        let agents = plistURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: agents, withIntermediateDirectories: true)

        let logs = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? fileManager.createDirectory(at: logs, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable.path],
            "RunAtLoad": true,
            "KeepAlive": false,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
            "StandardOutPath": logs.appendingPathComponent("FanLite.launchd.log").path,
            "StandardErrorPath": logs.appendingPathComponent("FanLite.launchd.log").path
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
        try data.write(to: plistURL, options: .atomic)
    }

    private static func remove() throws {
        guard fileManager.fileExists(atPath: plistURL.path) else { return }
        try fileManager.removeItem(at: plistURL)
    }
}
