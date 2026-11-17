import XCTest
@testable import Rattle

final class InsightStatsTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
    private func item(_ d: Date, words: Int, app: String = "App", bundle: String? = nil) -> HistoryItem {
        HistoryItem(date: d, raw: "", text: Array(repeating: "w", count: words).joined(separator: " "), duration: 10, appName: app, bundleID: bundle)
    }

    func testMonthComparisonUsesTheSameDaysOfLastMonth() {
        let now = date(2026, 11, 17)
        let h = [item(date(2026, 11, 2), words: 100), item(date(2026, 11, 16), words: 50),
                 item(date(2026, 10, 5), words: 40), item(date(2026, 10, 17), words: 10),   // inside the first 17 days
                 item(date(2026, 10, 25), words: 999)]                                       // after day 17: not counted
        let r = InsightStats.monthComparison(h, now: now, calendar: cal)
        XCTAssertEqual(r.thisMonth, 150)
        XCTAssertEqual(r.lastMonthSamePeriod, 50)
    }

    func testPercentChange() {
        XCTAssertEqual(InsightStats.percentChange(150, from: 50), 200)
        XCTAssertEqual(InsightStats.percentChange(25, from: 100), -75)
        XCTAssertNil(InsightStats.percentChange(10, from: 0))
    }

    func testSameAppUnderDifferentNamesCountsOnce() {
        let d = date(2026, 11, 1)
        let h = [item(d, words: 1, app: "Claude", bundle: "com.anthropic.claudefordesktop"),
                 item(d, words: 1, app: "claudefordesktop", bundle: "com.anthropic.claudefordesktop"),
                 item(d, words: 1, app: "Chrome", bundle: "com.google.Chrome"),
                 item(d, words: 1, app: "Google Chrome", bundle: "com.google.Chrome"),
                 item(d, words: 1, app: "Old import", bundle: nil)]
        XCTAssertEqual(InsightStats.distinctApps(h), 3)
    }

    func testHeatmapScaleIgnoresOneHugeDay() {
        let days = [200, 220, 240, 260, 280, 300, 320, 340, 360, 20000, 0, 0]
        let scale = InsightStats.heatmapScale(days)
        XCTAssertLessThan(scale, 1000)
        XCTAssertEqual(InsightStats.heatmapScale([]), 1)
        XCTAssertEqual(InsightStats.heatmapScale([0, 0]), 1)
    }

    func testAIAppsAreFiledAsAIPrompts() {
        for b in ["com.openai.codex", "com.t3tools.t3code", "com.google.antigravity-ide", "com.anthropic.claudefordesktop"] {
            XCTAssertEqual(InsightCategory.from(bundleID: b), .ai, b)
        }
        XCTAssertEqual(InsightCategory.from(bundleID: "com.google.Chrome"), .other)
    }

    func testHoursAndMinutes() {
        XCTAssertEqual(InsightStats.hoursAndMinutes(45), "45 min")
        XCTAssertEqual(InsightStats.hoursAndMinutes(125), "2 h 5 min")
    }
}
