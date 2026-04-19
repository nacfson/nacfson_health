#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// `live_activities` Flutter 플러그인 v2.4.3 은 고정된 ActivityAttributes 타입
/// (`LiveActivitiesAppAttributes`) 으로만 Activity 를 request 한다.
/// Widget extension 은 이 타입을 **동일한 이름·레이아웃** 으로 재선언해야
/// ActivityKit 이 매칭되는 `ActivityConfiguration` 을 찾을 수 있다.
///
/// 사용자 데이터(endAtMs, isPaused, exerciseName 등)는 ContentState 가 아니라
/// App Group `UserDefaults(suiteName:)` 에 `"\(activity.id)_\(key)"` 로 저장되고,
/// 위젯은 그걸 직접 읽어 표시한다.
@available(iOS 16.1, *)
public struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable {
        public var appGroupId: String
    }

    public var id = UUID()
}
#endif
