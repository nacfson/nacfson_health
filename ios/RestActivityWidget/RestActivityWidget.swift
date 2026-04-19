#if canImport(ActivityKit) && canImport(WidgetKit)
import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct RestActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            // Lock Screen / Banner
            RestLockScreenView(context: context)
                .padding()
                .activityBackgroundTint(Color(.systemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer")
                        .foregroundColor(.mint)
                        .imageScale(.large)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timerText(context: context)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                }
                DynamicIslandExpandedRegion(.center) {
                    if let name = context.attributes.exerciseName, !name.isEmpty {
                        Text(name)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("휴식 중")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    progressBar(context: context)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundColor(.mint)
            } compactTrailing: {
                timerText(context: context)
                    .monospacedDigit()
                    .foregroundColor(.primary)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundColor(.mint)
            }
        }
    }

    @ViewBuilder
    private func timerText(context: ActivityViewContext<RestActivityAttributes>) -> some View {
        let endDate = Date(timeIntervalSince1970: context.state.endAtMs / 1000.0)
        if context.state.isPaused {
            Text("일시정지")
                .font(.caption)
        } else {
            Text(timerInterval: Date()...endDate, countsDown: true)
        }
    }

    @ViewBuilder
    private func progressBar(
        context: ActivityViewContext<RestActivityAttributes>
    ) -> some View {
        let endDate = Date(timeIntervalSince1970: context.state.endAtMs / 1000.0)
        if context.state.isPaused {
            ProgressView(value: 0.0)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(.mint)
                Text(context.attributes.exerciseName ?? "휴식 중")
                    .font(.headline)
                Spacer()
                if context.state.isPaused {
                    Text("일시정지")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text(timerInterval: Date()...endDate, countsDown: true)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
            if !context.state.isPaused {
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
}
#endif
