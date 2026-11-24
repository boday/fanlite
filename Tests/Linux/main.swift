import Foundation

// Linux CI 進入點：只編譯純 Foundation 的政策邏輯，不依賴 AppKit。
exit(ThermalPolicy.selfTest() ? 0 : 1)
