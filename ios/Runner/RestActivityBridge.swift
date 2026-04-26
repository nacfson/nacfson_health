import Flutter
import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// 휴식 타이머 Live Activity 용 자체 ActivityAttributes.
///
/// Widget extension 의 `ios/RestActivityWidget/RestActivityAttributes.swift` 와
/// **동일한 이름·레이아웃** 으로 선언되어야 ActivityKit 이 매칭한다. ContentState 에
/// 타이머 데이터(endAtMs/isPaused/exerciseName/totalSeconds)를 직접 실어 매 update
/// 마다 ActivityKit 이 위젯 rebuild 를 즉시 trigger 한다.
@available(iOS 16.1, *)
public struct RestActivityAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable {
        public var endAtMs: Double
        public var isPaused: Bool
        public var exerciseName: String
        public var totalSeconds: Int
    }

    public var id = UUID()
}

/// 레거시 `live_activities` 플러그인 시절의 attribute 타입. 이전 버전에서 떠 있던
/// 잔여 Activity 를 cleanup 하기 위해 `endAll` 경로에서만 조회한다.
@available(iOS 16.1, *)
public struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable {
        public var appGroupId: String
    }

    public var id = UUID()
}

/// Flutter MethodChannel `nacfson/rest_activity` 핸들러.
///
/// ActivityKit 호출 일체를 Flutter 측에서 직접 사용하지 않고 이 bridge 로 통합한다.
/// `live_activities` 플러그인은 ContentState 가 `appGroupId` 단일 필드라 의미 있는
/// state 변경 update 를 일으키지 못해, 위젯 rebuild trigger 가 약했다. 자체 bridge 는
/// `RestActivityAttributes.ContentState` 로 매 update 마다 실제 데이터를 갱신한다.
///
/// 메서드:
/// - `start(totalSeconds, endAtMs, exerciseName)` → `activityId: String?`
/// - `update(activityId, endAtMs, isPaused, exerciseName?, totalSeconds?)`
/// - `endActivity(activityId)`
/// - `endAll()` (구버전 `LiveActivitiesAppAttributes` 잔여까지 정리)
/// - `areEnabled()` → `Bool`
/// - `scheduleDismiss(activityId, dismissAtMs)` (`Activity.end(.after)` 예약)
public final class RestActivityBridge {
    private static let channelName = "nacfson/rest_activity"
    private static let appGroupId = "group.com.nacfson.nacfsonHealth"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        channel.setMethodCallHandler { call, result in
            handle(call: call, result: result)
        }
    }

    private static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            guard #available(iOS 16.1, *) else { result(nil); return }
            guard let args = call.arguments as? [String: Any],
                  let totalSeconds = args["totalSeconds"] as? Int,
                  let endAtMs = args["endAtMs"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS",
                                    message: "totalSeconds/endAtMs required",
                                    details: nil))
                return
            }
            let exerciseName = (args["exerciseName"] as? String) ?? ""
            start(totalSeconds: totalSeconds,
                  endAtMs: endAtMs,
                  exerciseName: exerciseName,
                  result: result)

        case "update":
            guard #available(iOS 16.1, *) else { result(nil); return }
            guard let args = call.arguments as? [String: Any],
                  let activityId = args["activityId"] as? String,
                  let endAtMs = args["endAtMs"] as? Double,
                  let isPaused = args["isPaused"] as? Bool else {
                result(FlutterError(code: "INVALID_ARGS",
                                    message: "activityId/endAtMs/isPaused required",
                                    details: nil))
                return
            }
            let exerciseName = args["exerciseName"] as? String
            let totalSeconds = args["totalSeconds"] as? Int
            update(activityId: activityId,
                   endAtMs: endAtMs,
                   isPaused: isPaused,
                   exerciseName: exerciseName,
                   totalSeconds: totalSeconds,
                   result: result)

        case "endActivity":
            guard #available(iOS 16.1, *) else { result(nil); return }
            guard let args = call.arguments as? [String: Any],
                  let activityId = args["activityId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS",
                                    message: "activityId required",
                                    details: nil))
                return
            }
            endActivity(activityId: activityId, result: result)

        case "endAll":
            if #available(iOS 16.1, *) {
                endAll(result: result)
            } else {
                result(nil)
            }

        case "areEnabled":
            if #available(iOS 16.2, *) {
                result(ActivityAuthorizationInfo().areActivitiesEnabled)
            } else if #available(iOS 16.1, *) {
                result(ActivityAuthorizationInfo().areActivitiesEnabled)
            } else {
                result(false)
            }

        case "scheduleDismiss":
            guard let args = call.arguments as? [String: Any],
                  let activityId = args["activityId"] as? String,
                  let dismissAtMs = args["dismissAtMs"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS",
                                    message: "activityId/dismissAtMs required",
                                    details: nil))
                return
            }
            if #available(iOS 16.1, *) {
                scheduleDismiss(activityId: activityId, dismissAtMs: dismissAtMs, result: result)
            } else {
                result(nil)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @available(iOS 16.1, *)
    private static func start(
        totalSeconds: Int,
        endAtMs: Double,
        exerciseName: String,
        result: @escaping FlutterResult
    ) {
        // ActivityKit 권한 / 사용자 disable 체크. ActivityKit Settings 에서 OFF 면
        // .request 가 throw 한다 — 호출 전에 빠르게 거른다.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            NSLog("[LiveActivity] bridge start: areActivitiesEnabled=false")
            result(nil)
            return
        }

        let attributes = RestActivityAttributes()
        let state = RestActivityAttributes.ContentState(
            endAtMs: endAtMs,
            isPaused: false,
            exerciseName: exerciseName,
            totalSeconds: totalSeconds
        )
        let endDate = Date(timeIntervalSince1970: endAtMs / 1000.0)

        do {
            let activityId: String
            if #available(iOS 16.2, *) {
                let activity = try Activity<RestActivityAttributes>.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: endDate),
                    pushType: nil
                )
                activityId = activity.id
            } else {
                let activity = try Activity<RestActivityAttributes>.request(
                    attributes: attributes,
                    contentState: state,
                    pushType: nil
                )
                activityId = activity.id
            }
            NSLog("[LiveActivity] bridge start id=\(activityId) name=\"\(exerciseName)\" endAt=\(endDate)")
            result(activityId)
        } catch {
            NSLog("[LiveActivity] bridge start FAILED: \(error)")
            result(nil)
        }
    }

    @available(iOS 16.1, *)
    private static func update(
        activityId: String,
        endAtMs: Double,
        isPaused: Bool,
        exerciseName: String?,
        totalSeconds: Int?,
        result: @escaping FlutterResult
    ) {
        Task {
            var matched = false
            for activity in Activity<RestActivityAttributes>.activities where activity.id == activityId {
                matched = true
                let current = activity.contentState
                let newState = RestActivityAttributes.ContentState(
                    endAtMs: endAtMs,
                    isPaused: isPaused,
                    exerciseName: exerciseName ?? current.exerciseName,
                    totalSeconds: totalSeconds ?? current.totalSeconds
                )
                if #available(iOS 16.2, *) {
                    let endDate = Date(timeIntervalSince1970: endAtMs / 1000.0)
                    await activity.update(ActivityContent(state: newState, staleDate: endDate))
                } else {
                    await activity.update(using: newState)
                }
                NSLog("[LiveActivity] bridge update id=\(activityId) endAt=\(Date(timeIntervalSince1970: endAtMs / 1000.0)) paused=\(isPaused)")
            }
            if !matched {
                NSLog("[LiveActivity] bridge update id=\(activityId) NOT FOUND")
            }
            result(nil)
        }
    }

    @available(iOS 16.1, *)
    private static func endActivity(activityId: String, result: @escaping FlutterResult) {
        Task {
            for activity in Activity<RestActivityAttributes>.activities where activity.id == activityId {
                if #available(iOS 16.2, *) {
                    await activity.end(nil, dismissalPolicy: .immediate)
                } else {
                    await activity.end(dismissalPolicy: .immediate)
                }
                NSLog("[LiveActivity] bridge endActivity id=\(activityId)")
            }
            result(nil)
        }
    }

    /// 앱 시작 시 호출되어 이전 세션의 잔여 Activity 를 정리한다.
    /// 신규 `RestActivityAttributes` 와 레거시 `LiveActivitiesAppAttributes` 양쪽 조회.
    @available(iOS 16.1, *)
    private static func endAll(result: @escaping FlutterResult) {
        Task {
            var count = 0
            for activity in Activity<RestActivityAttributes>.activities {
                if #available(iOS 16.2, *) {
                    await activity.end(nil, dismissalPolicy: .immediate)
                } else {
                    await activity.end(dismissalPolicy: .immediate)
                }
                count += 1
            }
            for activity in Activity<LiveActivitiesAppAttributes>.activities {
                if #available(iOS 16.2, *) {
                    await activity.end(nil, dismissalPolicy: .immediate)
                } else {
                    await activity.end(dismissalPolicy: .immediate)
                }
                count += 1
            }
            NSLog("[LiveActivity] bridge endAll cleaned=\(count)")
            result(nil)
        }
    }

    @available(iOS 16.1, *)
    private static func scheduleDismiss(activityId: String, dismissAtMs: Double, result: @escaping FlutterResult) {
        let dismissDate = Date(timeIntervalSince1970: dismissAtMs / 1000.0)
        Task {
            var matched = false
            for activity in Activity<RestActivityAttributes>.activities where activity.id == activityId {
                matched = true
                let state = activity.contentState
                if #available(iOS 16.2, *) {
                    await activity.end(
                        ActivityContent(state: state, staleDate: dismissDate),
                        dismissalPolicy: .after(dismissDate)
                    )
                } else {
                    await activity.end(using: state, dismissalPolicy: .after(dismissDate))
                }
                NSLog("[LiveActivity] bridge scheduleDismiss id=\(activityId) at=\(dismissDate)")
            }
            if !matched {
                NSLog("[LiveActivity] bridge scheduleDismiss id=\(activityId) NOT FOUND")
            }
            result(nil)
        }
    }
}
