import WidgetKit
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// 운동 잔디밭 (Workout Heatmap) 홈스크린 위젯
//
// 데이터 채널: App Group `group.com.nacfson.nacfsonHealth` UserDefaults
//   key   : "heatmap_widget_data"
//   value : JSON {
//             "cells": [{"d":"YYYY-MM-DD","v":Double}, ... 91개],
//             "q1": Double, "q2": Double, "q3": Double,
//             "gridStart": "YYYY-M-D"
//           }
//
// Flutter 측 widget kind 는 "WorkoutHeatmapWidget" (HomeWidgetService.updateHeatmap)
// 색상 분기는 lib/features/summary/presentation/widgets/workout_heatmap_card.dart
// 의 _colorFor 와 동일하게 0 / q1 / q2 / q3 / 그 이상 5단계.
// ─────────────────────────────────────────────────────────────────────────────

private let appGroupId = "group.com.nacfson.nacfsonHealth"
private let heatmapDataKey = "heatmap_widget_data"

// AppTheme.colorMint (lib/core/theme/app_theme.dart:10)
private let heatmapMint = Color(red: 0x4F / 255.0, green: 0xD1 / 255.0, blue: 0xB6 / 255.0)

// 13주 × 7요일 = 91셀
private let weeks = 13
private let daysPerWeek = 7

// ── Payload ──────────────────────────────────────────────────────────────────

private struct HeatmapCellRaw: Decodable {
    let d: String
    let v: Double
}

private struct HeatmapPayload: Decodable {
    let cells: [HeatmapCellRaw]
    let q1: Double
    let q2: Double
    let q3: Double
    let gridStart: String?

    static let placeholder: HeatmapPayload = {
        var cs: [HeatmapCellRaw] = []
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(byAdding: .day, value: -(weeks * daysPerWeek - 1), to: Date()) ?? Date()
        for i in 0..<(weeks * daysPerWeek) {
            let d = cal.date(byAdding: .day, value: i, to: start) ?? start
            // 임의 패턴 — 미리보기/플레이스홀더용
            let v = (i % 5 == 0) ? 0.0 : Double((i * 37) % 100) * 50
            cs.append(HeatmapCellRaw(d: HeatmapPayload.fmt(d), v: v))
        }
        return HeatmapPayload(cells: cs, q1: 800, q2: 2000, q3: 4000, gridStart: HeatmapPayload.fmt(start))
    }()

    static func fmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

// ── Entry ────────────────────────────────────────────────────────────────────

struct WorkoutHeatmapEntry: TimelineEntry {
    let date: Date
    fileprivate let payload: HeatmapPayload

    static let placeholder = WorkoutHeatmapEntry(date: Date(), payload: .placeholder)
}

// ── Provider ─────────────────────────────────────────────────────────────────

struct WorkoutHeatmapProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutHeatmapEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutHeatmapEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutHeatmapEntry>) -> Void) {
        let entry = readEntry()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func readEntry() -> WorkoutHeatmapEntry {
        guard
            let raw = UserDefaults(suiteName: appGroupId)?.string(forKey: heatmapDataKey),
            let data = raw.data(using: .utf8),
            let payload = try? JSONDecoder().decode(HeatmapPayload.self, from: data)
        else {
            return .placeholder
        }
        return WorkoutHeatmapEntry(date: Date(), payload: payload)
    }
}

// ── Widget ───────────────────────────────────────────────────────────────────

struct WorkoutHeatmapWidget: Widget {
    /// HomeWidgetService 의 _iOSHeatmapWidgetName 과 일치해야 한다.
    let kind: String = "WorkoutHeatmapWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutHeatmapProvider()) { entry in
            HeatmapView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("운동 잔디")
        .description("최근 13주 운동 볼륨 히트맵")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// ── View ─────────────────────────────────────────────────────────────────────

struct HeatmapView: View {
    let entry: WorkoutHeatmapEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("운동 잔디")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(activeDays)일 / 91일")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            grid
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if family == .systemLarge {
                legend
            }
        }
    }

    // MARK: grid

    private var grid: some View {
        // 13열 × 7행. 각 열이 한 주(월~일).
        let cellSize: CGFloat = (family == .systemLarge) ? 14 : 9
        let gap: CGFloat = (family == .systemLarge) ? 4 : 2
        return HStack(alignment: .top, spacing: gap) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: gap) {
                    ForEach(0..<daysPerWeek, id: \.self) { dow in
                        cellAt(week: w, dow: dow)
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
    }

    private func cellAt(week: Int, dow: Int) -> some View {
        let idx = week * daysPerWeek + dow
        let v = (idx < entry.payload.cells.count) ? entry.payload.cells[idx].v : 0
        return RoundedRectangle(cornerRadius: 2.5)
            .fill(color(for: v))
    }

    private func color(for v: Double) -> Color {
        let q1 = entry.payload.q1
        let q2 = entry.payload.q2
        let q3 = entry.payload.q3
        if v <= 0 { return Color.gray.opacity(0.18) }
        if v < q1 || q1 == 0 { return heatmapMint.opacity(0.25) }
        if v < q2 { return heatmapMint.opacity(0.50) }
        if v < q3 { return heatmapMint.opacity(0.75) }
        return heatmapMint
    }

    private var activeDays: Int {
        entry.payload.cells.reduce(0) { $0 + ($1.v > 0 ? 1 : 0) }
    }

    // MARK: legend (large only)

    private var legend: some View {
        HStack(spacing: 6) {
            Text("적음").font(.caption2).foregroundStyle(.secondary)
            ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { a in
                RoundedRectangle(cornerRadius: 2)
                    .fill(heatmapMint.opacity(a))
                    .frame(width: 10, height: 10)
            }
            Text("많음").font(.caption2).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// ── Preview ──────────────────────────────────────────────────────────────────

#Preview("medium", as: .systemMedium) {
    WorkoutHeatmapWidget()
} timeline: {
    WorkoutHeatmapEntry.placeholder
}

#Preview("large", as: .systemLarge) {
    WorkoutHeatmapWidget()
} timeline: {
    WorkoutHeatmapEntry.placeholder
}
