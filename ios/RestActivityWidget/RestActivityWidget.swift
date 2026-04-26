#if canImport(ActivityKit) && canImport(WidgetKit)
import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct RestActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            RestLockScreenView(context: context)
                .padding()
        } dynamicIsland: { context in
            let endDate = Date(timeIntervalSince1970: context.state.endAtMs / 1000.0)
            let isPaused = context.state.isPaused
            let name = context.state.exerciseName

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer")
                        .foregroundColor(.mint)
                        .imageScale(.large)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimelineView(.periodic(from: Date(), by: 1)) { _ in
                        timerText(endDate: endDate, isPaused: isPaused)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.primary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(name.isEmpty ? "휴식 중" : name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TimelineView(.periodic(from: Date(), by: 1)) { _ in
                        progressBar(endDate: endDate, isPaused: isPaused)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundColor(.mint)
            } compactTrailing: {
                TimelineView(.periodic(from: Date(), by: 1)) { _ in
                    timerText(endDate: endDate, isPaused: isPaused)
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
    let context: ActivityViewContext<RestActivityAttributes>

    var body: some View {
        let endDate = Date(timeIntervalSince1970: context.state.endAtMs / 1000.0)
        let isPaused = context.state.isPaused
        let name = context.state.exerciseName

        TimelineView(.periodic(from: Date(), by: 1)) { _ in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: Date() >= endDate ? "checkmark.circle.fill" : "timer")
                        .foregroundColor(.mint)
                    Text(name.isEmpty ? (Date() >= endDate ? "휴식 완료" : "휴식 중") : name)
                        .font(.headline)
                    Spacer()
                    trailingLabel(endDate: endDate, isPaused: isPaused)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                if !isPaused && Date() < endDate {
                    ProgressView(
                        timerInterval: Date()...endDate,
                        countsDown: true,
                        label: { EmptyView() },
                        currentValueLabel: { EmptyView() }
                    )
                    .tint(.mint)
                } else if Date() >= endDate {
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
