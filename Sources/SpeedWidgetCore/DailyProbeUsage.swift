import Foundation

public struct DailyProbeUsage {
    private let defaults: UserDefaults
    private let calendar: Calendar

    private let dateKey = "probeBudgetDate"
    private let bytesKey = "probeBudgetBytes"

    public init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    public mutating func consumedBytes(now: Date = .now) -> Int {
        resetIfNeeded(now: now)
        return defaults.integer(forKey: bytesKey)
    }

    public mutating func record(_ bytes: Int, now: Date = .now) {
        let current = consumedBytes(now: now)
        defaults.set(current + max(0, bytes), forKey: bytesKey)
    }

    private mutating func resetIfNeeded(now: Date) {
        let today = calendar.startOfDay(for: now)
        let storedDate = defaults.object(forKey: dateKey) as? Date
        guard storedDate.map({ !calendar.isDate($0, inSameDayAs: today) }) ?? true else { return }
        defaults.set(today, forKey: dateKey)
        defaults.set(0, forKey: bytesKey)
    }
}
