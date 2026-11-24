import Foundation

// 與 App 共用同一份政策測試；Linux CI 直接編譯本檔＋ThermalPolicy.swift。
extension ThermalPolicy {
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


        // ---- v0.5.0 自訂曲線與防呆邊界 ----
        let custom = ThermalCurve(
            warmEnter: 75, hotEnter: 85, criticalEnter: 95,
            warmExit: 65, hotExit: 80, criticalExit: 90,
            normalRPM: 2500, warmRPM: 4000, hotRPM: 5000,
            criticalRPM: 5800, minimumDwell: 10
        )
        var s = ThermalPolicy(curve: custom)
        var sClock = Date(timeIntervalSince1970: 4_000_000)
        check("custom 74.9 normal", s.target(for: 74.9, now: sClock), 2500)
        check("custom 75 warm", s.target(for: 75, now: sClock), 4000)
        check("custom 85 hot", s.target(for: 85, now: sClock), 5000)
        check("custom 95 critical", s.target(for: 95, now: sClock), 5800)
        sClock.addTimeInterval(5)
        check("custom dwell 5s blocks exit", s.target(for: 64.9, now: sClock), 5800)
        sClock.addTimeInterval(6)
        check("custom dwell 11s -> hot", s.target(for: 64.9, now: sClock), 5000)

        // 非法曲線（進入門檻倒掛）必須回退預設，不得套用。
        let invalid = ThermalCurve(warmEnter: 90, hotEnter: 80, criticalEnter: 95)
        var t = ThermalPolicy(curve: invalid)
        check("invalid curve falls back: 80 warm", t.target(for: 80, now: Date(timeIntervalSince1970: 5_000_000)), 4500)

        print(failures == 0 ? "ALL POLICY TESTS PASS" : "POLICY TESTS FAILED: \(failures)")
        return failures == 0
    }
}
