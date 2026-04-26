#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// 휴식 타이머 Live Activity 의 attribute 타입.
///
/// `RestActivityBridge` (Runner) 와 Widget Extension 양쪽에 **동일한 이름·레이아웃** 으로
/// 선언해야 ActivityKit 이 매칭되는 `ActivityConfiguration` 을 찾는다. ContentState 에
/// 타이머 데이터를 직접 실어 보내, 매 update 마다 ActivityKit 이 위젯 rebuild 를
/// 즉시 trigger 하도록 한다.
@available(iOS 16.1, *)
public struct RestActivityAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable {
        public var endAtMs: Double
        public var isPaused: Bool
        public var exerciseName: String
        public var totalSeconds: Int

        public init(endAtMs: Double, isPaused: Bool, exerciseName: String, totalSeconds: Int) {
            self.endAtMs = endAtMs
            self.isPaused = isPaused
            self.exerciseName = exerciseName
            self.totalSeconds = totalSeconds
        }
    }

    public var id = UUID()

    public init() {}
}

/// 레거시 `live_activities` 플러그인 시절의 attribute 타입.
/// 이전 버전 빌드에서 떠 있던 잔여 Activity 를 정리하기 위해 cleanup 경로에서만 조회한다.
/// 신규 Activity 는 `RestActivityAttributes` 로만 만든다.
@available(iOS 16.1, *)
public struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable {
        public var appGroupId: String
    }

    public var id = UUID()
}
#endif
