import WidgetKit
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// 영양(칼로리·탄단지) 홈스크린 위젯
//
// 데이터 채널: App Group `group.com.nacfson.nacfsonHealth` UserDefaults
//   key   : "nutrition_widget_data"
//   value : JSON string (HomeWidgetService.update() 가 저장)
//
// Flutter 측에서 widget kind 를 "NacfsonHealthWidget" 으로 호출하므로
// `Widget.kind` 와 `HomeWidget.updateWidget(iOSName: ...)` 이 일치해야 한다.
// 참고: lib/core/widget/home_widget_service.dart
// ─────────────────────────────────────────────────────────────────────────────

private let appGroupId = "group.com.nacfson.nacfsonHealth"
private let nutritionDataKey = "nutrition_widget_data"

// AppTheme.colorMint (lib/core/theme/app_theme.dart:10) 와 동일 RGB
private let mint = Color(red: 0x4F / 255.0, green: 0xD1 / 255.0, blue: 0xB6 / 255.0)
private let mintDeep = Color(red: 0x2B / 255.0, green: 0xAF / 255.0, blue: 0x95 / 255.0)

// ── Entry ────────────────────────────────────────────────────────────────────

struct NutritionEntry: TimelineEntry {
    let date: Date
    let calories: Int
    let targetCalories: Int
    let carbs: Double
    let targetCarbs: Double
    let protein: Double
    let targetProtein: Double
    let fat: Double
    let targetFat: Double

    static let placeholder = NutritionEntry(
        date: Date(),
        calories: 1240, targetCalories: 2200,
        carbs: 140, targetCarbs: 280,
        protein: 95, targetProtein: 140,
        fat: 38, targetFat: 70
    )
}

// ── Provider ─────────────────────────────────────────────────────────────────

struct NutritionProvider: TimelineProvider {
    func placeholder(in context: Context) -> NutritionEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (NutritionEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NutritionEntry>) -> Void) {
        let entry = readEntry()
        // 1시간 후 fallback refresh — 앱이 명시적으로 갱신을 요청하지 못한 경우.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func readEntry() -> NutritionEntry {
        guard
            let raw = UserDefaults(suiteName: appGroupId)?.string(forKey: nutritionDataKey),
            let data = raw.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .placeholder
        }
        func i(_ k: String) -> Int { (json[k] as? Int) ?? Int((json[k] as? Double) ?? 0) }
        func d(_ k: String) -> Double { (json[k] as? Double) ?? Double((json[k] as? Int) ?? 0) }
        return NutritionEntry(
            date: Date(),
            calories: i("calories"),
            targetCalories: max(1, i("targetCalories")),
            carbs: d("carbs"),
            targetCarbs: max(1, d("targetCarbs")),
            protein: d("protein"),
            targetProtein: max(1, d("targetProtein")),
            fat: d("fat"),
            targetFat: max(1, d("targetFat"))
        )
    }
}

// ── Widget ───────────────────────────────────────────────────────────────────

struct NutritionWidget: Widget {
    /// HomeWidgetService 의 _iOSWidgetName 과 일치해야 한다.
    let kind: String = "NacfsonHealthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NutritionProvider()) { entry in
            NutritionWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("오늘의 영양")
        .description("칼로리·탄단지 진행률을 한눈에")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// ── View ─────────────────────────────────────────────────────────────────────

struct NutritionWidgetView: View {
    let entry: NutritionEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium: mediumView
        default:            smallView
        }
    }

    // MARK: small

    private var smallView: some View {
        let progress = min(1.0, Double(entry.calories) / Double(entry.targetCalories))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("오늘 영양")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "flame.fill")
                    .foregroundStyle(mint)
                    .imageScale(.small)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .stroke(mint.opacity(0.18), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(mint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(entry.calories)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("/ \(entry.targetCalories) kcal")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: medium

    private var mediumView: some View {
        let cal = min(1.0, Double(entry.calories) / Double(entry.targetCalories))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("오늘 영양")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entry.calories)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("/ \(entry.targetCalories) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: cal)
                .tint(mint)
            HStack(spacing: 10) {
                macroBar(label: "탄", v: entry.carbs,   t: entry.targetCarbs,   color: mint)
                macroBar(label: "단", v: entry.protein, t: entry.targetProtein, color: mintDeep)
                macroBar(label: "지", v: entry.fat,     t: entry.targetFat,     color: .orange)
            }
        }
    }

    private func macroBar(label: String, v: Double, t: Double, color: Color) -> some View {
        let p = min(1.0, v / max(1.0, t))
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text("\(Int(v))g")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            ProgressView(value: p)
                .tint(color)
        }
    }
}

// ── Preview ──────────────────────────────────────────────────────────────────

#Preview("small", as: .systemSmall) {
    NutritionWidget()
} timeline: {
    NutritionEntry.placeholder
}

#Preview("medium", as: .systemMedium) {
    NutritionWidget()
} timeline: {
    NutritionEntry.placeholder
}
