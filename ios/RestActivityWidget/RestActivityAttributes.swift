#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Live Activity payload for the rest timer.
///
/// `exerciseName` is fixed at activity creation. `endAt` / `isPaused`
/// are pushed via `Activity.update(...)` from the Flutter side via
/// the `live_activities` plugin.
@available(iOS 16.1, *)
struct RestActivityAttributes: ActivityAttributes {
    public typealias RestTimerStatus = ContentState

    public struct ContentState: Codable, Hashable {
        /// 휴식 종료 예정 시각 (Unix epoch ms). SwiftUI `Text(timerInterval:)`로 자동 카운트다운.
        var endAtMs: Double
        var isPaused: Bool
        var totalSeconds: Int
    }

    /// 운동 종목명 (선택). Lock Screen / Expanded 뷰의 라벨로 사용.
    var exerciseName: String?
}
#endif
