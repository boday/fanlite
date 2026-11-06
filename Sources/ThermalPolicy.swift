import Foundation

enum ThermalLevel: String {
    case normal
    case warm
    case hot
    case critical

    var rank: Int {
        switch self {
        case .normal: return 0
        case .warm: return 1
        case .hot: return 2
        case .critical: return 3
        }
    }
}

struct ThermalPolicy {
    let normalRPM: Int
    let warmRPM: Int
    let hotRPM: Int
    let criticalRPM: Int
    let minimumDwell: TimeInterval
    private(set) var level: ThermalLevel = .normal
    private var lastChange: Date

    init(
        normalRPM: Int = 3000,
        warmRPM: Int = 4500,
        hotRPM: Int = 5500,
        criticalRPM: Int = 6000,
        minimumDwell: TimeInterval = 45
    ) {
        self.normalRPM = normalRPM
        self.warmRPM = warmRPM
        self.hotRPM = hotRPM
        self.criticalRPM = criticalRPM
        self.minimumDwell = minimumDwell
        // 初始設為很久以前，讓第一次降階不會被 dwell 阻擋。
        self.lastChange = Date(timeIntervalSince1970: 0)
    }

    /// 溫度進入門檻：80 / 88 / 90°C，升階立即生效。
    /// 降階門檻：70 / 82 / 85°C，且必須在目前階層停留至少 `minimumDwell` 秒。
    /// 80°C 增壓退出門檻刻意壓到 70°C：滿載時 4,500 RPM 的平衡溫度約 74–80°C，
    /// 若用 74°C 當退出點仍會在負載中反覆降回 3,000 RPM。
    mutating func target(for temperature: Double, now: Date = Date()) -> Int {
        let previous = level

        switch level {
        case .normal:
            if temperature >= 90 {
                level = .critical
            } else if temperature >= 88 {
                level = .hot
            } else if temperature >= 80 {
                level = .warm
            }
        case .warm:
            if temperature >= 90 {
                level = .critical
            } else if temperature >= 88 {
                level = .hot
            } else if temperature < 70 {
                level = .normal
            }
        case .hot:
            if temperature >= 90 {
                level = .critical
            } else if temperature < 82 {
                level = .warm
            }
        case .critical:
            if temperature < 85 {
                level = .hot
            }
        }

        if level.rank < previous.rank {
            let elapsed = now.timeIntervalSince(lastChange)
            if elapsed < minimumDwell {
                level = previous
            } else {
                lastChange = now
            }
        } else if level.rank > previous.rank {
            lastChange = now
        }

        switch level {
        case .normal: return normalRPM
        case .warm: return warmRPM
        case .hot: return hotRPM
        case .critical: return criticalRPM
        }
    }

    static func selfTest() -> Bool {
        var failures = 0
        func check(_ name: String, _ actual: Int, _ expected: Int) {
            let ok = actual == expected
            print("\(ok ? "PASS" : "FAIL") \(name): got \(actual), expected \(expected)")
            if !ok { failures += 1 }
        }

        var clock = Date(timeIntervalSince1970: 1_000_000)
        func advance(_ seconds: TimeInterval) { clock.addTimeInterval(seconds) }

        var p = ThermalPolicy()
        check("70°C normal", p.target(for: 70, now: clock), 3000)
        check("79.9°C normal", p.target(for: 79.9, now: clock), 3000)
        check("80°C warm", p.target(for: 80, now: clock), 4500)
        check("85°C warm", p.target(for: 85, now: clock), 4500)
        check("88°C hot", p.target(for: 88, now: clock), 5500)
        check("89.9°C hot", p.target(for: 89.9, now: clock), 5500)
        check("90°C critical", p.target(for: 90, now: clock), 6000)
        check("critical 85.1°C stays", p.target(for: 85.1, now: clock), 6000)

        // 降階 dwell：剛升到 critical，立刻降到 84.9 不應降階。
        advance(10)
        check("dwell blocks critical downshift", p.target(for: 84.9, now: clock), 6000)
        advance(36)
        check("critical exit 84.9°C after dwell", p.target(for: 84.9, now: clock), 5500)

        // hot -> warm 需 <82 且 dwell 45 秒。
        advance(10)
        check("dwell blocks hot downshift", p.target(for: 81.9, now: clock), 5500)
        advance(36)
        check("hot exit 81.9°C after dwell", p.target(for: 81.9, now: clock), 4500)

        // warm -> normal 需 <70 且 dwell 45 秒；76°C 應留在 warm。
        advance(10)
        check("warm stays 76°C", p.target(for: 76, now: clock), 4500)
        check("warm stays 70.1°C", p.target(for: 70.1, now: clock), 4500)
        check("dwell blocks warm downshift", p.target(for: 69.9, now: clock), 4500)
        advance(36)
        check("warm exit 69.9°C after dwell", p.target(for: 69.9, now: clock), 3000)

        // 升階不受 dwell 限制。
        var q = ThermalPolicy()
        var qClock = Date(timeIntervalSince1970: 2_000_000)
        check("fresh 80 warm", q.target(for: 80, now: qClock), 4500)
        qClock.addTimeInterval(1)
        check("immediate hot upgrade", q.target(for: 88, now: qClock), 5500)
        qClock.addTimeInterval(1)
        check("immediate critical upgrade", q.target(for: 90, now: qClock), 6000)

        // 降到 69.9 但未滿 45 秒，仍應維持 warm；超過後才回 normal。
        var r = ThermalPolicy()
        var rClock = Date(timeIntervalSince1970: 3_000_000)
        check("r 80 warm", r.target(for: 80, now: rClock), 4500)
        rClock.addTimeInterval(20)
        check("r 69.9 dwell block", r.target(for: 69.9, now: rClock), 4500)
        rClock.addTimeInterval(26)
        check("r 69.9 after dwell normal", r.target(for: 69.9, now: rClock), 3000)

        print(failures == 0 ? "ALL POLICY TESTS PASS" : "POLICY TESTS FAILED: \(failures)")
        return failures == 0
    }
}
