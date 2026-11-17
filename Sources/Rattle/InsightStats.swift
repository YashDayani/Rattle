import AppKit
import Foundation

/// Pure calculations behind the Insights page, kept out of the views so they can be tested.
enum InsightStats {
    /// Words dictated so far this month, and in the same stretch of last month (day 1 through today's day number), so a month that
    /// is only a few days old is not compared against a whole finished one.
    static func monthComparison(_ history: [HistoryItem], now: Date = Date(), calendar cal: Calendar = .current) -> (thisMonth: Int, lastMonthSamePeriod: Int) {
        guard let lastMonth = cal.date(byAdding: .month, value: -1, to: now) else { return (0, 0) }
        let day = cal.component(.day, from: now)
        var this = 0, last = 0
        for h in history {
            if cal.isDate(h.date, equalTo: now, toGranularity: .month) { this += h.words }
            else if cal.isDate(h.date, equalTo: lastMonth, toGranularity: .month), cal.component(.day, from: h.date) <= day { last += h.words }
        }
        return (this, last)
    }

    /// Percentage change, or nil when there is nothing to compare with.
    static func percentChange(_ now: Int, from before: Int) -> Int? {
        before > 0 ? Int((Double(now - before) / Double(before) * 100).rounded()) : nil
    }

    /// One key per app. The same app shows up under several names ("Claude" and "claudefordesktop"), so the bundle id decides.
    static func appKey(_ h: HistoryItem) -> String { (h.bundleID?.lowercased()).flatMap { $0.isEmpty ? nil : $0 } ?? h.appName.lowercased() }

    static func distinctApps(_ history: [HistoryItem]) -> Int { Set(history.map(appKey)).count }

    /// The name shown for an app: its installed name when it is on this Mac, otherwise the name it was most often recorded under.
    static func displayName(forKey key: String, in history: [HistoryItem]) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) {
            let name = FileManager.default.displayName(atPath: url.path)
            return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        }
        var counts: [String: Int] = [:]
        for h in history where appKey(h) == key { counts[h.appName, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key ?? key
    }

    /// Words per day for the heatmap's colour scale: the 90th percentile of active days, so one huge day does not wash out the rest.
    static func heatmapScale(_ wordsPerDay: [Int]) -> Int {
        let v = wordsPerDay.filter { $0 > 0 }.sorted()
        guard !v.isEmpty else { return 1 }
        return max(1, v[Int((Double(v.count - 1) * 0.9).rounded(.down))])
    }

    static func hoursAndMinutes(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}
