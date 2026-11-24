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

/// 可持久化、可編輯的風扇曲線。所有溫度單位為 °C，RPM 為 target。
struct ThermalCurve: Codable, Equatable {
    var warmEnter: Double = 80
    var hotEnter: Double = 88
    var criticalEnter: Double = 90
    var warmExit: Double = 70
    var hotExit: Double = 82
    var criticalExit: Double = 85
    var normalRPM: Int = 3000
    var warmRPM: Int = 4500
    var hotRPM: Int = 5500
    var criticalRPM: Int = 6000
    var minimumDwell: TimeInterval = 45

    static let `default` = ThermalCurve()

    /// 防呆：進入門檻必須嚴格遞增，退出門檻必須低於對應進入門檻，
    /// RPM 必須單調不減；不符合時拒絕套用並回退預設曲線。
    var isValid: Bool {
        warmEnter < hotEnter && hotEnter < criticalEnter &&
        warmExit < warmEnter && hotExit < hotEnter && criticalExit < criticalEnter &&
        normalRPM > 0 && warmRPM >= normalRPM && hotRPM >= warmRPM && criticalRPM >= hotRPM &&
        minimumDwell >= 0
    }
}

struct ThermalPolicy {
    let curve: ThermalCurve
    private(set) var level: ThermalLevel = .normal
    private var lastChange: Date

    init(curve: ThermalCurve = .default) {
        self.curve = curve.isValid ? curve : .default
        // 初始設為很久以前，讓第一次降階不會被 dwell 阻擋。
        self.lastChange = Date(timeIntervalSince1970: 0)
    }

    /// 升階立即生效；降階需低於出場門檻且停留至少 `curve.minimumDwell` 秒。
    /// 80°C 的退出門檻壓到 70°C：實測滿載 4,500 RPM 平衡點約 74–80°C，
    /// 若用 74°C 當退出點仍會在負載中反覆降回 3,000 RPM。
    mutating func target(for temperature: Double, now: Date = Date()) -> Int {
        let previous = level

        switch level {
        case .normal:
            if temperature >= curve.criticalEnter {
                level = .critical
            } else if temperature >= curve.hotEnter {
                level = .hot
            } else if temperature >= curve.warmEnter {
                level = .warm
            }
        case .warm:
            if temperature >= curve.criticalEnter {
                level = .critical
            } else if temperature >= curve.hotEnter {
                level = .hot
            } else if temperature < curve.warmExit {
                level = .normal
            }
        case .hot:
            if temperature >= curve.criticalEnter {
                level = .critical
            } else if temperature < curve.hotExit {
                level = .warm
            }
        case .critical:
            if temperature < curve.criticalExit {
                level = .hot
            }
        }

        if level.rank < previous.rank {
            let elapsed = now.timeIntervalSince(lastChange)
            if elapsed < curve.minimumDwell {
                level = previous
            } else {
                lastChange = now
            }
        } else if level.rank > previous.rank {
            lastChange = now
        }

        switch level {
        case .normal: return curve.normalRPM
        case .warm: return curve.warmRPM
        case .hot: return curve.hotRPM
        case .critical: return curve.criticalRPM
        }
    }
}
