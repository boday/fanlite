import Foundation

enum ThermalLevel: String {
    case normal
    case warm
    case hot
    case critical
}

struct ThermalPolicy {
    let normalRPM: Int
    let warmRPM: Int
    let hotRPM: Int
    let criticalRPM: Int
    private(set) var level: ThermalLevel = .normal

    init(normalRPM: Int = 3000, warmRPM: Int = 4500, hotRPM: Int = 5500, criticalRPM: Int = 6000) {
        self.normalRPM = normalRPM
        self.warmRPM = warmRPM
        self.hotRPM = hotRPM
        self.criticalRPM = criticalRPM
    }

    mutating func target(for temperature: Double) -> Int {
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
            } else if temperature < 76 {
                level = .normal
            }
        case .hot:
            if temperature >= 90 {
                level = .critical
            } else if temperature < 84 {
                level = .warm
            }
        case .critical:
            if temperature < 86 {
                level = .hot
            }
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

        var p = ThermalPolicy()
        check("70°C normal", p.target(for: 70), 3000)
        check("79.9°C normal", p.target(for: 79.9), 3000)
        check("80°C warm", p.target(for: 80), 4500)
        check("85°C warm", p.target(for: 85), 4500)
        check("88°C hot", p.target(for: 88), 5500)
        check("89.9°C hot", p.target(for: 89.9), 5500)
        check("90°C critical", p.target(for: 90), 6000)
        check("critical hysteresis 86", p.target(for: 86), 6000)
        check("critical exit 85.9", p.target(for: 85.9), 5500)
        check("hot exit 84.1 stays hot", p.target(for: 84.1), 5500)
        check("hot exit 83.9 warm", p.target(for: 83.9), 4500)
        check("warm exit 75.9 normal", p.target(for: 75.9), 3000)

        var q = ThermalPolicy()
        check("fresh 80 warm", q.target(for: 80), 4500)
        check("warm stays at 79", q.target(for: 79), 4500)
        check("warm still 76", q.target(for: 76), 4500)
        check("warm drops 75.9", q.target(for: 75.9), 3000)

        print(failures == 0 ? "ALL POLICY TESTS PASS" : "POLICY TESTS FAILED: \(failures)")
        return failures == 0
    }
}
