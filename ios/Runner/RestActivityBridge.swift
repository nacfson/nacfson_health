import Flutter
import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// Flutter MethodChannel `nacfson/rest_activity` 핸들러.
///
/// - `scheduleDismiss(activityId, dismissAtMs)`:
///   지정한 Activity 를 `dismissAtMs` 시각에 iOS 가 자동으로 제거하도록
///   `activity.end(dismissalPolicy: .after(date))` 를 호출. 앱이 suspend/kill 된
///   상태에서도 iOS 시스템이 해당 시각에 Activity 를 dismiss 한다.
///
/// 플러그인 `live_activities` 는 `Activity.end(dismissalPolicy: .immediate)` 만
/// 노출하므로, 백그라운드 자동 소멸을 위해 별도 브리지가 필요하다.
///
/// 타입 주의: `LiveActivitiesAppAttributes` 는 플러그인 내부 nested struct 로 선언돼
/// Runner 에서 직접 import 할 수 없다. ActivityKit 은 구조체 이름(모듈 비포함)으로
/// Activity 를 매칭하므로, Runner 에도 동일 이름의 top-level struct 를 선언하면
/// `Activity<LiveActivitiesAppAttributes>.activities` 조회가 플러그인 생성분을 포함한다.
/// (Widget Extension 쪽 `ios/RestActivityWidget/RestActivityAttributes.swift` 와 동일 패턴)
@available(iOS 16.1, *)
public struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable {
        public var appGroupId: String
    }

    public var id = UUID()
}

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
        case "scheduleDismiss":
            guard let args = call.arguments as? [String: Any],
                  let activityId = args["activityId"] as? String,
                  let dismissAtMs = args["dismissAtMs"] as? Double else {
                result(FlutterError(code: "INVALID_ARGS", message: "activityId/dismissAtMs required", details: nil))
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
    private static func scheduleDismiss(activityId: String, dismissAtMs: Double, result: @escaping FlutterResult) {
        let dismissDate = Date(timeIntervalSince1970: dismissAtMs / 1000.0)
        Task {
            var matched = false
            for activity in Activity<LiveActivitiesAppAttributes>.activities where activity.id == activityId {
                matched = true
                let state = LiveActivitiesAppAttributes.LiveDeliveryData(appGroupId: appGroupId)
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
