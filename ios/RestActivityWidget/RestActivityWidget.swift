#if canImport(ActivityKit) && canImport(WidgetKit)
import ActivityKit
import SwiftUI
import WidgetKit

/// App Group 은 Runner / Widget Extension / entitlements 에 등록된 값과 일치해야 한다.
private let appGroupId = "group.com.nacfson.nacfsonHealth"

/// 플러그인이 App Group UserDefaults 에 `"\(activity.id)_\(key)"` 로 저장한 사용자 데이터.
/// 플러그인 소스 `LiveActivitiesPlugin.swift:261` 참고.
@available(iOS 16.1, *)
private func readRestPrefs(
    _ context: ActivityViewContext<LiveActivitiesAppAttributes>
) -> (endDate: Date, isPaused: Bool, name: String) {
    let defaults = UserDefaults(suiteName: appGroupId)
    let prefix = context.attributes.id.uuidString
    let endAtMs = defaults?.double(forKey: "\(prefix)_endAtMs") ?? 0
    let isPaused = defaults?.bool(forKey: "\(prefix)_isPaused") ?? false
    let name = defaults?.string(forKey: "\(prefix)_exerciseName") ?? ""
    let endDate = Date(timeIntervalSince1970: endAtMs / 1000.0)
    return (endDate, isPaused, name)
}

@available(iOS 16.1, *)
struct RestActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            RestLockScreenView(context: context)
                .padding()
                .activityBackgroundTint(Color(.systemBackground))
        } dynamicIsland: { context in
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer")
                        .foregroundColor(.mint)
                        .imageScale(.large)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimelineView(.periodic(from: Date(), by: 1)) { _ in
                        let prefs = readRestPrefs(context)
                        timerText(endDate: prefs.endDate, isPaused: prefs.isPaused)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.primary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    let prefs = readRestPrefs(context)
                    Text(prefs.name.isEmpty ? "휴식 중" : prefs.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TimelineView(.periodic(from: Date(), by: 1)) { _ in
                        let prefs = readRestPrefs(context)
                        progressBar(endDate: prefs.endDate, isPaused: prefs.isPaused)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundColor(.mint)
            } compactTrailing: {
                TimelineView(.periodic(from: Date(), by: 1)) { _ in
                    let prefs = readRestPrefs(context)
                    timerText(endDate: prefs.endDate, isPaused: prefs.isPaused)
                        .monospacedDigit()
                        .foregroundColor(.primary)
                }
            } minimal: {
                Image(systemName: "timer")
                    .foregroundColor(.mint)
            }
        }
    }

    @ViewBuilder
    private func timerText(endDate: Date, isPaused: Bool) -> some View {
        if isPaused {
            Text("일시정지")
                .font(.caption)
        } else if Date() >= endDate {
            Text("완료")
                .font(.caption)
                .foregroundColor(.mint)
        } else {
            Text(timerInterval: Date()...endDate, countsDown: true)
        }
    }

    @ViewBuilder
    private func progressBar(endDate: Date, isPaused: Bool) -> some View {
        if isPaused || Date() >= endDate {
            ProgressView(value: isPaused ? 0.0 : 1.0)
                .tint(.mint)
        } else {
            ProgressView(
                timerInterval: Date()...endDate,
                countsDown: true,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .tint(.mint)
        }
    }
}

@available(iOS 16.1, *)
struct RestLockScreenView: View {
    let context: ActivityViewContext<LiveActivitiesAppAttributes>

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { _ in
            let prefs = readRestPrefs(context)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: Date() >= prefs.endDate ? "checkmark.circle.fill" : "timer")
                        .foregroundColor(.mint)
                    Text(prefs.name.isEmpty ? (Date() >= prefs.endDate ? "휴식 완료" : "휴식 중") : prefs.name)
                        .font(.headline)
                    Spacer()
                    trailingLabel(endDate: prefs.endDate, isPaused: prefs.isPaused)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                if !prefs.isPaused && Date() < prefs.endDate {
                    ProgressView(
                        timerInterval: Date()...prefs.endDate,
                        countsDown: true,
                        label: { EmptyView() },
                        currentValueLabel: { EmptyView() }
                    )
                    .tint(.mint)
                } else if Date() >= prefs.endDate {
                    ProgressView(value: 1.0)
                        .tint(.mint)
                }
            }
        }
    }

    @ViewBuilder
    private func trailingLabel(endDate: Date, isPaused: Bool) -> some View {
        if isPaused {
            Text("일시정지")
                .font(.subheadline)
                .foregroundColor(.secondary)
        } else if Date() >= endDate {
            Text("완료")
                .foregroundColor(.mint)
        } else {
            Text(timerInterval: Date()...endDate, countsDown: true)
        }
    }
}
#endif
