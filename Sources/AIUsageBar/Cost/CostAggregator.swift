import Foundation

enum Window: String, CaseIterable, Identifiable {
    case today, days7, days30, month, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: return "Today"; case .days7: return "7 days"
        case .days30: return "30 days"; case .month: return "This month"; case .all: return "All time"
        }
    }
    /// Inclusive local-time start; nil start means "everything".
    func start(now: Date = Date(), cal: Calendar = .current) -> Date? {
        switch self {
        case .today:  return cal.startOfDay(for: now)
        case .days7:  return cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))
        case .days30: return cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now))
        case .month:  return cal.date(from: cal.dateComponents([.year, .month], from: now))
        case .all:    return nil
        }
    }
}

struct ProjectSpend: Identifiable { let project: String; let cost: Double; let calls: Int; var id: String { project } }
struct ModelSpend: Identifiable { let model: String; let cost: Double; let calls: Int; var id: String { model } }
struct DayPoint: Identifiable { let day: Date; let cost: Double; var id: Date { day } }

struct WindowSummary {
    var totalCost = 0.0
    var input = 0, output = 0, cacheRead = 0, cacheWrite = 0
    var calls = 0
    var sessions = 0
    var byProject: [ProjectSpend] = []
    var byModel: [ModelSpend] = []
    var days: [DayPoint] = []
    var unpricedModels: Set<String> = []
}

enum CostAggregator {
    static func summary(events: [UsageEvent], pricing: Pricing = .shared,
                        window: Window, project: String? = nil,
                        now: Date = Date(), cal: Calendar = .current) -> WindowSummary {
        let start = window.start(now: now, cal: cal)
        var s = WindowSummary()
        var projCost: [String: (Double, Int)] = [:]
        var modelCost: [String: (Double, Int)] = [:]
        var dayCost: [Date: Double] = [:]
        var sessionIds = Set<String>()

        for e in events {
            if let start, e.timestamp < start { continue }
            if let project, e.project != project { continue }
            let c = pricing.cost(for: e, unpriced: &s.unpricedModels)
            s.totalCost += c
            s.input += e.input; s.output += e.output
            s.cacheRead += e.cacheRead; s.cacheWrite += e.cacheWrite
            s.calls += 1
            if !e.sessionId.isEmpty { sessionIds.insert(e.sessionId) }
            projCost[e.project, default: (0,0)].0 += c
            projCost[e.project]!.1 += 1
            modelCost[e.model, default: (0,0)].0 += c
            modelCost[e.model]!.1 += 1
            let day = cal.startOfDay(for: e.timestamp)
            dayCost[day, default: 0] += c
        }
        s.sessions = max(sessionIds.count, 0)
        s.byProject = projCost.map { ProjectSpend(project: $0.key, cost: $0.value.0, calls: $0.value.1) }
            .sorted { $0.cost > $1.cost }
        s.byModel = modelCost.map { ModelSpend(model: $0.key, cost: $0.value.0, calls: $0.value.1) }
            .sorted { $0.cost > $1.cost }
        s.days = dayCost.map { DayPoint(day: $0.key, cost: $0.value) }.sorted { $0.day < $1.day }
        return s
    }
}
